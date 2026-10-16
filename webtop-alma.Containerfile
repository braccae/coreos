# Webtop (Alma) — remote KDE Plasma desktop streamed with Selkies.
#
# Native AlmaLinux build. KDE Plasma comes from EPEL (Plasma 6.6.4 — the same
# series the linuxserver fedora-kde reference image ships), and Selkies is
# installed from PyPI into its own venv.
#
# Nothing is copied out of the linuxserver images. Selkies 2.x bundles its own
# web dashboard (selkies/selkies_web) and serves it from the same aiohttp
# process as the websocket, so there is no nginx front-end, no /lsiopy venv
# copy, and no source patch. The desktop session is launched by Selkies' own
# `selkies-session` supervisor, which brings up Selkies' compositor and nests
# the Plasma session (from /usr/share/wayland-sessions) inside it.
FROM ghcr.io/braccae/alma:latest

# --- KDE Plasma 6 desktop, Wayland + Xwayland, audio ------------------------
# plasma-workspace/plasma-desktop/kwin are 6.6.4 in EPEL 10. Xwayland and mesa
# are needed for X11 client apps; pipewire + wireplumber are the audio stack.
RUN dnf install -y \
        plasma-workspace \
        plasma-desktop \
        kwin \
        kdecoration \
        plasma-breeze \
        breeze-icon-theme \
        polkit-kde \
        konsole \
        qt6-qtwayland \
        xorg-x11-server-Xwayland \
        libxcvt \
        mesa-dri-drivers \
        mesa-libEGL \
        dejavu-sans-fonts \
        pipewire \
        wireplumber \
        pipewire-pulseaudio \
        pulseaudio-utils \
        alsa-utils \
    && dnf clean all

# --- Selkies streaming server (from PyPI; bundles the web dashboard) ---------
# UV_CACHE_DIR is set because the base image has no writable HOME cache; a
# private venv keeps Selkies off the system Python.
ENV UV_CACHE_DIR=/tmp/uv-cache
RUN uv venv /opt/selkies --python python3 && \
    uv pip install --python /opt/selkies/bin/python --no-cache "selkies==2.0.0" && \
    rm -rf /tmp/uv-cache

# --- webtop user ------------------------------------------------------------
# The `video` group (GID 39) is provided by systemd-sysusers on this bootc base:
# it resolves via NSS but is NOT in /etc/group on disk. useradd/usermod/gpasswd
# all validate against /etc/group directly, so `useradd -G wheel,video` fails
# and `usermod -aG video` silently no-ops. Materialize the group in /etc/group
# first, then add membership by GID.
RUN useradd -m -u 1000 -G wheel webtop && \
    grep -q '^video:' /etc/group || echo 'video:x:39:' >> /etc/group; \
    usermod -aG 39 webtop && \
    usermod -U webtop && \
    passwd -d webtop && \
    echo "webtop ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/webtop

# Phase 2 adds rootfs/webtop-alma/ (systemd unit + launcher) and the quadlet.

ENTRYPOINT ["/usr/lib/systemd/systemd"]
