FROM ghcr.io/ublue-os/bazzite:stable-44 as base

USER root

# Cloudflare WARP client. The repo file is vendored in repos/ and installed
# here because this image does not COPY the repos/ directory. Units are left
# disabled: the client needs registration, so admins opt in with
# `systemctl enable --now warp-svc`.
# Bazzite ships /opt as a symlink to var/opt and /var/opt is absent, so create
# it first or rpm cannot unpack /opt/cloudflare-warp (cpio: mkdir failed).
COPY repos/cloudflare-warp.repo /etc/yum.repos.d/
RUN mkdir -p /var/opt && \
    dnf5 install -y --setopt=install_weak_deps=False cloudflare-warp && \
    systemctl disable warp-svc && \
    dnf5 clean all

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
    systemctl disable systemd-resolved.service 2>/dev/null; true

# Webtop User setup
RUN useradd -m -u 1000 -G wheel webtop && \
    usermod -U webtop && \
    passwd -d webtop && \
    echo "webtop ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/webtop

RUN systemctl disable plasmalogin.service sddm.service 2>/dev/null || true; \
    chmod +x /usr/local/bin/start-webtop.sh \
              /usr/local/bin/webtop-gpu-report \
              /usr/local/bin/webtop-appimage-run && \
    (setcap -r /usr/bin/kwin_wayland || true) && \
    systemctl enable webtop.service

ENTRYPOINT [ "/usr/lib/systemd/systemd" ]
