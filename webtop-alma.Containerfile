# Webtop (Alma) — remote KDE Plasma desktop streamed with Selkies.
#
# Native AlmaLinux build. KDE Plasma comes from EPEL (Plasma 6.6.x), and
# Selkies 2.1 (with its pixelflux compositor and pcmflux audio engine) is
# installed from PyPI into its own venv.
#
# Nothing is copied out of the linuxserver images. Selkies 2.x bundles its own
# web dashboard (selkies/selkies_web) and serves it from the same aiohttp
# process as the websocket, so there is no nginx front-end and no /lsiopy venv
# copy. The session is started explicitly by start-webtop.sh: selkies brings up
# its compositor (wayland-1), kwin_wayland nests on it (wayland-0), and
# plasmashell runs inside. startplasma-wayland is not used because its
# systemd-managed target cannot be restarted inside a container.
FROM ghcr.io/braccae/alma:latest

# --- KDE Plasma 6 desktop, Wayland + Xwayland, audio ------------------------
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-webtop-alma-deps && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Selkies streaming server (from PyPI via uv; bundles web dashboard) -----
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-selkies 2.1.0 true

# --- Local session overlay (late for optimal layer caching) -----------------
# webtop.service + launcher scripts; see rootfs/webtop-alma/.
COPY rootfs/webtop-alma/ /

# --- Final configuration: core user, factory /etc sync, KDE defaults, units -
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile configure-webtop-alma

ENTRYPOINT ["/usr/lib/systemd/systemd"]
