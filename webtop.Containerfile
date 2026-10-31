FROM ghcr.io/ublue-os/bazzite:stable-43 as base

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

# Install dependencies for building selkies and wtype, and nginx
RUN dnf5 install -y \
    nginx \
    gcc gcc-c++ make cmake git \
    cairo-devel wayland-devel wayland-protocols-devel \
    python3-pip python3-devel \
    mesa-dri-drivers pciutils vte291 \
    jq tar gzip ca-certificates curl && \
    dnf5 clean all

# Copy linuxserver components
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /usr/share/selkies /usr/share/selkies
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /lsiopy /lsiopy
RUN ln -sf /usr/bin/python3 /lsiopy/bin/python3
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /usr/lib/selkies_joystick_interposer.so /usr/lib/
COPY --from=lscr.io/linuxserver/webtop:fedora-kde /opt/lib/libudev.so.1.0.0-fake /opt/lib/
# kwin-xwayland.py is NOT copied from the linuxserver image any more: upstream
# stopped shipping /kwin-xwayland.py, and this repo has its own copy in
# rootfs/webtop/usr/local/bin/kwin-xwayland.py (installed by the overlay COPY
# below, before the chmod/entrypoint steps).

# Build selkies-desktop since binary from F44 fails on F40/F43 glibc
RUN git clone https://github.com/selkies-project/selkies-desktop.git /tmp/selkies-desktop && \
    cd /tmp/selkies-desktop && make && mv selkies-desktop /usr/bin/selkies-desktop && \
    rm -rf /tmp/selkies-desktop

# Setup frontend web folder
RUN rm -rf /usr/share/selkies/web && \
    cp -a /usr/share/selkies/selkies-dashboard /usr/share/selkies/web && \
    cp /usr/share/selkies/www/icon.png /usr/share/selkies/web/favicon.ico || true && \
    echo '{ "name": "Webtop", "short_name": "Webtop", "manifest_version": 2, "version": "1.0.0", "display": "fullscreen", "start_url": "/" }' > /usr/share/selkies/web/manifest.json

# Copy local overlay
COPY rootfs/common/ /
COPY rootfs/webtop/ /

# Run the selkies.py patch
RUN python3 /usr/local/bin/patch-selkies.py && rm -f /usr/local/bin/patch-selkies.py

# Replace nginx default config
RUN rm -f /etc/nginx/conf.d/default.conf

# Webtop User setup
RUN useradd -m -u 1000 -G wheel webtop && \
    usermod -U webtop && \
    passwd -d webtop && \
    echo "webtop ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/webtop

RUN chmod +x /usr/local/bin/start-webtop.sh /usr/local/bin/kwin-xwayland.py && \
    (setcap -r /usr/bin/kwin_wayland || true) && \
    systemctl enable webtop.service

ENTRYPOINT [ "/usr/lib/systemd/systemd" ]