#!/usr/bin/env bash
# Webtop session launcher — KDE Plasma nested in Selkies' built-in compositor.
#
# Model (aligned with linuxserver/webtop:fedora-kde on selkies 2.1):
#   * selkies/pixelflux provides the outer compositor on WAYLAND_DISPLAY=wayland-1
#   * kwin_wayland runs nested on it and provides wayland-0 plus Xwayland (:0)
#   * plasmashell, kded6, kcminit and the portal helpers run inside that session
# nginx stays in front: it serves the dashboard on :3000 and proxies /websocket
# to selkies on :8082.
set -euo pipefail

# Rendering device permissions (only when /dev/dri is passed through).
for dev in /dev/dri/renderD*; do
    [ -e "$dev" ] || continue
    chown webtop:video "$dev" 2>/dev/null || true
    chmod 660 "$dev" 2>/dev/null || true
done

mkdir -p /home/webtop
chown -R webtop:webtop /home/webtop

# Dashboard + websocket proxy front-end (root owns the listener on :3000).
nginx -c /etc/nginx/nginx.conf

# --- session environment (inherited by the unprivileged session) ------------
export HOME=/home/webtop
export XDG_RUNTIME_DIR=/tmp/xdg-webtop
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export XDG_MENU_PREFIX=plasma-
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM=wayland
export SHELL=/bin/bash
export MOZ_ENABLE_WAYLAND=0
# KWin needs this to start inside the container without polkit/permission checks.
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export DISPLAY=:0

# --- streaming server settings ---------------------------------------------
export PIXELFLUX_WAYLAND=true
export SELKIES_MODE=websockets
export SELKIES_ADDR=127.0.0.1
export SELKIES_PORT=8082
# No browser login: the dashboard is the only entry point (matches the previous
# behaviour of this image). Set SELKIES_ENABLE_BASIC_AUTH=true to require one.
export SELKIES_ENABLE_BASIC_AUTH="${SELKIES_ENABLE_BASIC_AUTH:-false}"
export SELKIES_ENCODER="${SELKIES_ENCODER:-h264enc,h265enc,vp8enc,vp9enc,av1enc,jpeg}"
export SELKIES_RATE_CONTROL_MODE="${SELKIES_RATE_CONTROL_MODE:-crf,cbr}"
# Software encoding when no GPU render node is available.
if [ ! -e /dev/dri/renderD128 ]; then
    export SELKIES_USE_CPU=true
fi

# --- runtime sockets --------------------------------------------------------
rm -rf /tmp/.X11-unix/X0
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
mkdir -p "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR"/wayland-*
chown webtop:webtop "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# --- session (unprivileged user, private session bus) ----------------------
# The session shell deliberately runs without `set -u`: KDE's own
# plasma-workspace env scripts reference unset variables (for example
# GDK_CORE_DEVICE_EVENTS) and would abort the session.
setpriv --reuid=webtop --regid=webtop --init-groups -- dbus-run-session bash -c '
set -eo pipefail
export XDG_RUNTIME_DIR=/tmp/xdg-webtop
export KDE_SESSION_UID="$(id -u)"

mkdir -p "$HOME/.config"

# --- first-run KDE defaults ------------------------------------------------
if [ ! -f "$HOME/.config/kwinrc" ]; then
    kwriteconfig6 --file "$HOME/.config/kwinrc" --group Compositing --key Enabled false
fi
if [ ! -f "$HOME/.config/kscreenlockerrc" ]; then
    kwriteconfig6 --file "$HOME/.config/kscreenlockerrc" --group Daemon --key Autolock false
fi
if [ ! -f "$HOME/.config/kdeglobals" ]; then
    kwriteconfig6 --file "$HOME/.config/kdeglobals" --group KDE --key LookAndFeelPackage org.fedoraproject.fedora.desktop
fi

# --- KWin rule: wl-clipboard helper windows stay out of the task list ------
KWIN_RULES_FILE="$HOME/.config/kwinrulesrc"
RULE_DESC="wl-clipboard support"
if ! grep -q "$RULE_DESC" "$KWIN_RULES_FILE" 2>/dev/null; then
    RULE_ID=$(uuidgen)
    count=$(kreadconfig6 --file "$KWIN_RULES_FILE" --group General --key count --default 0)
    new_count=$((count + 1))
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key count "$new_count"
    existing_rules=$(kreadconfig6 --file "$KWIN_RULES_FILE" --group General --key rules)
    if [ -z "$existing_rules" ]; then
        kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key rules "$RULE_ID"
    else
        kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key rules "$existing_rules,$RULE_ID"
    fi
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key Description "$RULE_DESC"
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key wmclass "wl-(copy|paste)"
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key wmclassmatch 3
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skiptaskbar --type bool "true"
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skiptaskbarrule 2
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skipswitcher --type bool "true"
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skipswitcherrule 2
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key fsplevel 3
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key fsplevelrule 2
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key noborder --type bool "true"
    kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key noborderrule 2
fi

# --- session directories, theme, plasma env --------------------------------
setterm blank 0 2>/dev/null || true
setterm powerdown 0 2>/dev/null || true
mkdir -p "$HOME/.config/autostart" "$HOME/.config/kdedefaults" "$HOME/.local/share"
touch "$HOME/.local/share/user-places.xbel"
export XDG_CONFIG_DIRS="$HOME/.config/kdedefaults:${XDG_CONFIG_DIRS:-/etc/xdg}"
XCURSOR_THEME=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme --default breeze_cursors)
XCURSOR_SIZE=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorSize --default 24)
export XCURSOR_THEME XCURSOR_SIZE

for ENV_SCRIPT in /etc/xdg/plasma-workspace/env/*.sh "$HOME"/.config/plasma-workspace/env/*.sh; do
    [ -r "$ENV_SCRIPT" ] && . "$ENV_SCRIPT"
done

kbuildsycoca6 > /dev/null 2>&1 || true

# --- audio: pipewire first, then wireplumber on a clean LD_PRELOAD ---------
pipewire &
for _ in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/pipewire-0" ] && break; sleep 0.1; done
LD_PRELOAD= wireplumber &
pipewire-pulse &

# --- selkies: built-in compositor on wayland-1 -----------------------------
/opt/selkies/bin/selkies --addr="$SELKIES_ADDR" --mode=websockets --port="$SELKIES_PORT" &
SELKIES_PID=$!

for _ in $(seq 1 600); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.1; done
if [ ! -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
    echo "selkies compositor socket wayland-1 never appeared" >&2
    exit 1
fi

# --- KWin nested on wayland-1, providing wayland-0 and Xwayland :0 ---------
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
' > /tmp/webtop.log 2>&1
