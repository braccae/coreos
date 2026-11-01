FROM ghcr.io/ublue-os/bazzite:stable-44 AS plasma-nm-builder

# plasma-nm 6.7.5 draws "network-unavailable" for Tun/Veth devices, which is
# exactly what a container uplink is (pasta tap / netavark veth). Rebuild the
# Fedora SRPM with a small patch so the tray reflects the managed connection.
RUN dnf5 install -y dnf5-plugins rpm-build && dnf5 clean all
COPY build/plasma-nm /tmp/plasma-nm
# /root is a dangling symlink to /var/roothome on this base, so keep the
# rpmbuild tree under /tmp and point rpmbuild at it explicitly.
RUN mkdir -p /tmp/srpm /tmp/rpmbuild/BUILD /tmp/rpmbuild/RPMS /tmp/rpmbuild/SOURCES /tmp/rpmbuild/SPECS /tmp/rpmbuild/SRPMS && \
    dnf5 download --source plasma-nm --destdir /tmp/srpm && \
    rpm -i --define "_topdir /tmp/rpmbuild" /tmp/srpm/plasma-nm-*.src.rpm && \
    sed -i 's/^Release:.*/Release: 1%{?dist}.webtop1/' /tmp/rpmbuild/SPECS/plasma-nm.spec && \
    cp /tmp/plasma-nm/0001-plasma-nm-treat-tun-veth-as-wired.patch /tmp/rpmbuild/SOURCES/ && \
    sed -i '/^Release:/a Patch0: 0001-plasma-nm-treat-tun-veth-as-wired.patch' /tmp/rpmbuild/SPECS/plasma-nm.spec && \
    dnf5 builddep -y /tmp/rpmbuild/SPECS/plasma-nm.spec && \
    rpmbuild -bb --nodeps --define "_topdir /tmp/rpmbuild" /tmp/rpmbuild/SPECS/plasma-nm.spec

# Dogfood the published workstation image (same bazzite base plus this
# repository's desktop configuration) instead of the bare ublue base.
FROM ghcr.io/braccae/workstation:latest as base

USER root

# Cloudflare WARP client. The repo file is vendored in repos/ and installed
# here because this image does not COPY the repos/ directory. The daemon is
# enabled so the client can initialise; a registration is per-user and must be
# created once with `warp-cli registration new` (it lives in /var).
# Bazzite ships /opt as a symlink to var/opt and /var/opt is absent, so create
# it first or rpm cannot unpack /opt/cloudflare-warp (cpio: mkdir failed).
COPY repos/cloudflare-warp.repo /etc/yum.repos.d/
RUN mkdir -p /var/opt && \
    dnf5 install -y --setopt=install_weak_deps=False cloudflare-warp && \
    systemctl enable warp-svc && \
    dnf5 clean all

# --- patched plasma-nm -------------------------------------------------------
COPY --from=plasma-nm-builder /tmp/rpmbuild/RPMS/ /tmp/plasma-nm-rpms/
# Upgrade only the plasma-nm subpackages the base image already has; the SRPM
# also emits VPN plugins/debuginfo that should not be pulled in. dnf5's
# "upgrade <rpm>" ignores local files, so install each existing package by path.
RUN set -e; \
    rpms=""; \
    for rpm in /tmp/plasma-nm-rpms/*/plasma-nm-*.rpm; do \
        name=$(rpm -qp --qf '%{NAME}' "$rpm"); \
        case "$name" in *-debuginfo) continue;; esac; \
        if rpm -q "$name" >/dev/null 2>&1; then rpms="$rpms $rpm"; fi; \
    done; \
    rpm -Uvh --replacepkgs --oldpackage $rpms; \
    rm -rf /tmp/plasma-nm-rpms

# Runtime dependencies: nginx front-end, mesa/pciutils for the compositor,
# xhost for KWin's Xwayland, and the venv tooling for Selkies.
RUN dnf5 install -y \
    nginx \
    python3-pip \
    mesa-dri-drivers \
    pciutils \
    vte291 \
    jq tar gzip ca-certificates curl \
    xorg-x11-xauth \
    vulkan-tools \
    && dnf5 clean all

# --- Selkies streaming server -----------------------------------------------
# selkies 2.1 brings its own Wayland compositor (pixelflux) and audio engine
# (pcmflux), so the server is installed from PyPI into a pinned venv instead of
# copying the linuxserver /lsiopy python tree. The previous selkies-desktop
# build is gone: the session launched here never invoked it, and its repository
# no longer ships a Makefile.
ENV UV_CACHE_DIR=/tmp/uv-cache
# Use /usr/bin/python3 explicitly: rootfs/common/ copies usr/sbin/, which turns
# Bazzite's /usr/sbin -> bin symlink into a real directory, so a venv built from
# the PATH entry /usr/sbin/python3 would end up with a dangling interpreter.
RUN /usr/bin/python3 -m venv /opt/selkies && \
    /opt/selkies/bin/pip install --no-cache-dir "selkies==2.1.0" && \
    rm -rf /tmp/uv-cache

# Native input/webcam interposers come from the linuxserver reference image,
# which runs the same selkies 2.1 release. The python tree and the static
# dashboard are NOT copied: the venv pins selkies/pixelflux/pcmflux and selkies
# serves its own bundled dashboard.
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /usr/lib/selkies_input_interposer.so /usr/lib/
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /usr/lib/selkies_v4l2_interposer.so /usr/lib/
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /opt/lib/libudev.so.1.0.0-fake /opt/lib/
# Upstream ships the joystick interposer as a copy of the input one.
RUN ln -sf selkies_input_interposer.so /usr/lib/selkies_joystick_interposer.so

# Interposer and capture defaults shared by the session launcher.
ENV SELKIES_INTERPOSER=/usr/lib/selkies_input_interposer.so \
    SELKIES_WEBCAM_INTERPOSER=/usr/lib/selkies_v4l2_interposer.so \
    PIXELFLUX_WAYLAND=true

# Copy local overlay
COPY rootfs/common/ /
COPY rootfs/webtop/ /

# Replace nginx default config
RUN rm -f /etc/nginx/conf.d/default.conf

# --- container DNS ----------------------------------------------------------
# podman provides /etc/resolv.conf for the container. NetworkManager would
# replace it with the container's DHCP DNS (typically 169.254.1.1) and
# systemd-resolved has no usable upstream inside the container, while Fedora's
# nsswitch then stops at "resolve [!UNAVAIL=return]" before reaching "dns".
# Keep podman's resolv.conf and resolve through it directly.
RUN mkdir -p /etc/NetworkManager/conf.d && \
    printf '[main]\ndns=none\n' > /etc/NetworkManager/conf.d/99-webtop-dns.conf && \
    sed -i 's/^hosts:.*/hosts:      files dns/' /etc/nsswitch.conf && \
    if [ -d /usr/share/factory/etc ]; then \
        cp -a /etc/nsswitch.conf /usr/share/factory/etc/nsswitch.conf; \
    fi && \
    systemctl disable systemd-resolved.service 2>/dev/null; true

# Webtop User setup
RUN useradd -m -u 1000 -G wheel webtop && \
    usermod -U webtop && \
    passwd -d webtop && \
    echo "webtop ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/webtop

# Unprivileged ping: Fedora's iputils ships no file capabilities and the
# container's ping_group_range is 65534 only, so `ping` as webtop fails with
# "Operation not permitted". Setting cap_net_raw on the binary makes iputils
# try SOCK_RAW, which rootless pasta cannot grant, so instead widen the
# ping_group_range in /etc/sysctl.d/50-webtop-ping.conf.
# Steam's runtime calls /sbin/ldconfig; Fedora 44 ships /usr/bin/ldconfig only,
# which makes the client abort in surface_linux.cpp (glXChooseVisual).
RUN systemctl disable plasmalogin.service sddm.service 2>/dev/null || true; \
    systemctl disable cardwired.service 2>/dev/null || true; \
    chmod +x /usr/local/bin/start-webtop.sh \
              /usr/local/bin/webtop-gpu-report \
              /usr/local/bin/webtop-appimage-run \
              /usr/local/bin/webtop-nm-uplink && \
    (setcap -r /usr/bin/kwin_wayland || true) && \
    ([ -e /usr/sbin/ldconfig ] || ln -s ../bin/ldconfig /usr/sbin/ldconfig) && \
    systemctl enable webtop.service webtop-nm-uplink.service \
                     webtop-flatpak-appstream.service; \
    # bootc-style /etc persistence: /etc is a volume, and the base image ships
    # etc-overlay-sync to seed it from /usr/share/factory/etc at boot. Enable it
    # so image updates reach the persisted /etc. The factory copy of
    # nsswitch.conf is updated above so the DNS fix is not reverted.
    systemctl enable etc-overlay-sync.service 2>/dev/null || true

ENTRYPOINT [ "/usr/lib/systemd/systemd" ]
