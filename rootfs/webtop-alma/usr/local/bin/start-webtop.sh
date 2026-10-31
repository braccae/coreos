#!/usr/bin/env bash
# Webtop (Alma) session launcher — KDE Plasma nested in Selkies' compositor.
#
# Same model as rootfs/webtop/start-webtop.sh: selkies/pixelflux owns the outer
# compositor (wayland-1), kwin_wayland nests on it (wayland-0 + Xwayland), and
# plasmashell/kded/kcminit run inside that session. This unit already runs as
# `core`, so the only privilege step is the dbus session wrapper.
#
# We deliberately do NOT use startplasma-wayland / selkies-session: in container
# mode startplasma-wayland talks to the user systemd manager to start
# plasma-workspace-wayland.target, and after a service restart that transaction
# is refused ("TransactionIsDestructive"), leaving KWin without a session.
set -euo pipefail

export HOME="${HOME:-/home/core}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export XDG_MENU_PREFIX=plasma-
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export KDE_SESSION_UID="$(id -u)"
export QT_QPA_PLATFORM=wayland
export SHELL=/bin/bash
export MOZ_ENABLE_WAYLAND=0
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export DISPLAY=:0

# --- streaming server settings ---------------------------------------------
export PIXELFLUX_WAYLAND=true
export SELKIES_ADDR=0.0.0.0
export SELKIES_PORT=3000
export SELKIES_BASIC_AUTH_PASSWORD="${SELKIES_BASIC_AUTH_PASSWORD:-webtop}"
export SELKIES_BASIC_AUTH_ENABLED="${SELKIES_BASIC_AUTH:-true}"
export SELKIES_ENCODER="${SELKIES_ENCODER:-h264enc,h265enc,vp8enc,vp9enc,av1enc,jpeg}"
export SELKIES_RATE_CONTROL_MODE="${SELKIES_RATE_CONTROL_MODE:-crf,cbr}"
if [ ! -e /dev/dri/renderD128 ]; then
    export SELKIES_USE_CPU=true
fi

# --- runtime sockets --------------------------------------------------------
# /tmp/.X11-unix is usually created by tmpfiles as root; a non-root service
# cannot chmod it, so treat all of this as best effort.
rm -f /tmp/.X11-unix/X0 2>/dev/null || true
mkdir -p /tmp/.X11-unix 2>/dev/null || true
chmod 1777 /tmp/.X11-unix 2>/dev/null || true
mkdir -p "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR"/wayland-*
chmod 0700 "$XDG_RUNTIME_DIR"

# --- session ---------------------------------------------------------------
# A systemd user manager may already own the session bus; prefer it so KDE's
# systemd-activated portal can start, otherwise take a private bus.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

# shellcheck disable=SC2016
exec dbus-run-session bash -c '
set -eo pipefail

mkdir -p "$HOME/.config"

# Plasma env scripts (no set -u: they reference unset variables).
for ENV_SCRIPT in /etc/xdg/plasma-workspace/env/*.sh "$HOME"/.config/plasma-workspace/env/*.sh; do
    [ -r "$ENV_SCRIPT" ] && . "$ENV_SCRIPT"
done

kbuildsycoca6 > /dev/null 2>&1 || true

# --- audio -----------------------------------------------------------------
pipewire &
for _ in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/pipewire-0" ] && break; sleep 0.1; done
LD_PRELOAD= wireplumber &
pipewire-pulse &

# --- selkies: built-in compositor on wayland-1 -----------------------------
/opt/selkies/bin/selkies --addr="$SELKIES_ADDR" --port="$SELKIES_PORT" \
    --enable-basic-auth="$SELKIES_BASIC_AUTH_ENABLED" &
SELKIES_PID=$!

for _ in $(seq 1 600); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.1; done
if [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    echo "selkies compositor socket wayland-1 never appeared" >&2
    exit 1
fi

# --- KWin nested on wayland-1 ----------------------------------------------
WAYLAND_DISPLAY=wayland-1 kwin_wayland --no-lockscreen --xwayland &
KWIN_PID=$!

for _ in $(seq 1 600); do [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && break; sleep 0.1; done
if [ ! -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    echo "KWin wayland socket wayland-0 never appeared" >&2
    exit 1
fi
export WAYLAND_DISPLAY=wayland-0
dbus-update-activation-environment --all 2>/dev/null || true

# --- polkit agent ----------------------------------------------------------
if [ -f /usr/lib/libexec/polkit-kde-authentication-agent-1 ]; then
    /usr/lib/libexec/polkit-kde-authentication-agent-1 &
elif [ -f /usr/libexec/polkit-kde-authentication-agent-1 ]; then
    /usr/libexec/polkit-kde-authentication-agent-1 &
fi

# --- desktop ---------------------------------------------------------------
kcminit_startup &
kded6 &
xembedsniproxy &
gmenudbusmenuproxy &
plasmashell &
PLASMA_PID=$!

for _ in $(seq 1 300); do
    if dbus-send --session --print-reply --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
        string:org.kde.plasmashell 2>/dev/null | grep -q true; then
        break
    fi
    sleep 0.1
done
xdg-user-dirs-update || true
xhost +si:localuser:root >/dev/null 2>&1 || true

for ENTRY in "$HOME"/.config/autostart/*.desktop; do
    [ -f "$ENTRY" ] || continue
    grep -q "^Hidden=true" "$ENTRY" && continue
    ENTRY_CMD=$(grep -m1 "^Exec=" "$ENTRY" | cut -d= -f2- | sed "s/ %[a-zA-Z]//g")
    [ -n "$ENTRY_CMD" ] && bash -c "$ENTRY_CMD" &
done

wait "$PLASMA_PID"
kill "$KWIN_PID" "$SELKIES_PID" 2>/dev/null || true
'
