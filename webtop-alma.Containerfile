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
# dbus-daemon provides /usr/bin/dbus-run-session on EL 10 (it lives in
# dbus-tools on Fedora) — /usr/libexec/plasma-dbus-run-session-if-needed execs
# it before startplasma-wayland, so without it the Plasma session never starts.
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
        dbus-daemon \
    && dnf clean all

# --- Selkies streaming server (from PyPI; bundles the web dashboard) ---------
# UV_CACHE_DIR is set because the base image has no writable HOME cache; a
# private venv keeps Selkies off the system Python.
ENV UV_CACHE_DIR=/tmp/uv-cache
RUN uv venv /opt/selkies --python python3 && \
    uv pip install --python /opt/selkies/bin/python --no-cache "selkies==2.0.0" && \
    rm -rf /tmp/uv-cache

# --- core user ---------------------------------------------------------------
# The base image ships NO user: `core` is only provisioned in the *disk* image,
# via build/config-img.toml. Create it here so the desktop session, SSH and
# podman.socket (SocketGroup=core) all line up. The base already enables linger
# for core (/var/lib/systemd/linger/core) and points sshd's host keys at
# /var/lib/sshd, so nothing else needs adding for SSH or user services.
#
# Container mode has two traps:
#
#  * etc-overlay-sync.service (ConditionVirtualization=container) copies the
#    immutable snapshot /usr/share/factory/etc over /etc on every boot, so a
#    plain `useradd` is discarded and systemd fails with "User=core" 217/USER.
#    Create the account in /etc, then refresh the factory snapshot from it.
#  * `video`/`render` (GID 39/105) come from systemd-sysusers: they resolve via
#    NSS but are NOT in /etc/group on disk, and useradd/usermod/gpasswd validate
#    against /etc/group directly — so `useradd -G wheel,video` fails and
#    `usermod -aG video` silently no-ops. Materialize the group lines first,
#    then add membership by name.
#
# The home directory is left at the useradd default (/var/home/core): /home is a
# symlink to var/home in the base image, so that is the same directory the unit's
# HOME and the quadlet's /home/core volume resolve to, and `useradd -m` creates
# the missing /var/home for us.
RUN groupadd -g 1000 core && \
    useradd -m -u 1000 -g 1000 -G wheel -s /bin/bash core && \
    grep -q '^video:'  /etc/group || echo 'video:x:39:'   >> /etc/group; \
    grep -q '^render:' /etc/group || echo 'render:x:105:' >> /etc/group; \
    usermod -aG video,render core && \
    echo 'core:webtop' | chpasswd && \
    echo "core ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/core && \
    cp -a /etc/passwd /etc/group /etc/shadow /etc/gshadow /usr/share/factory/etc/ && \
    cp -a /etc/sudoers.d/core /usr/share/factory/etc/sudoers.d/core

# --- session overlay ---------------------------------------------------------
# webtop.service + the launcher; see rootfs/webtop-alma/.
COPY rootfs/webtop-alma/ /

# Selkies' dashboard uploads into $HOME/Desktop; create the XDG dirs up front so
# the first connection does not log "Could not create upload directory".
RUN mkdir -p /home/core/Desktop /home/core/Downloads /etc/webtop-alma && \
    chown -R core:core /home/core && \
    chmod +x /usr/local/bin/start-webtop.sh && \
    systemctl enable webtop.service

ENTRYPOINT ["/usr/lib/systemd/systemd"]
