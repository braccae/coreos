#!/usr/bin/env bash
# Webtop session launcher — KDE Plasma, streamed by Selkies.
#
# Runs as the `core` user (uid 1000) from webtop.service. We do NOT start a
# display manager (no SDDM/greeter) — selkies-session reads the desktop session
# straight from /usr/share/wayland-sessions and launches it once the compositor
# is up. That is what "no login screen" means here: the Plasma session starts
# directly and Selkies is the only display.
#
# selkies-session is the supervisor. It starts the sound server, starts the
# Selkies compositor, waits for the Wayland socket, runs the desktop, and tears
# everything down on exit. Everything after --session=plasma is passed straight
# through to `selkies`.
set -euo pipefail

# --- runtime environment -----------------------------------------------------
# Linger is enabled for core in the base image, so user@1000.service (and thus
# /run/user/1000) is up before we start. Fall back to a private dir if not.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR}" ]; then
    XDG_RUNTIME_DIR="$(mktemp -d /tmp/xdg-runtime.XXXXXX)"
    chmod 700 "$XDG_RUNTIME_DIR"
fi
export XDG_RUNTIME_DIR

export HOME="${HOME:-/home/core}"
export XDG_CURRENT_DESKTOP=KDE
export DESKTOP_SESSION=plasma

# --- streaming ---------------------------------------------------------------
# selkies-session defaults to an X11 backend and refuses to start without Xvfb;
# force the Wayland backend so it brings up its own compositor instead.
export SELKIES_WAYLAND=true

# selkies-session wraps the desktop in dbus-run-session unless a session bus is
# already advertised. The systemd user manager (user@1000.service) owns
# $XDG_RUNTIME_DIR/bus, and Plasma needs *that* bus to reach
# org.freedesktop.systemd1 — point at it instead of spawning a private one.
if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

# Selkies has basic auth ON by default and refuses to start without a password.
# Default to "webtop"; override with SELKIES_BASIC_AUTH_PASSWORD in the unit's
# environment file (/etc/webtop-alma/session.env). To serve without a web login
# at all, set SELKIES_BASIC_AUTH=false.
export SELKIES_BASIC_AUTH_PASSWORD="${SELKIES_BASIC_AUTH_PASSWORD:-webtop}"
basic_auth="${SELKIES_BASIC_AUTH:-true}"

# --- session -----------------------------------------------------------------
# The dashboard (selkies_web) is served by Selkies itself on this port — there
# is no nginx in front of it. The quadlet publishes 3000:3000.
exec /opt/selkies/bin/selkies-session \
    --session=plasma \
    --addr=0.0.0.0 \
    --port=3000 \
    --enable-basic-auth="${basic_auth}"
