#!/usr/bin/env bash
set -e

# Permissions setup for rendering devices
chown webtop:video /dev/dri/renderD* || true
chmod 660 /dev/dri/renderD* || true

# Ensure correct permissions on the home directory
mkdir -p /home/webtop
chown -R webtop:webtop /home/webtop

# Start NGINX as root
nginx -c /etc/nginx/nginx.conf

# Setup global environment variables
export HOME=/home/webtop
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export KDE_SESSION_VERSION=6
unset DISPLAY
export DISPLAY=:1
export XCURSOR_THEME=breeze_cursors

# Setup Selkies environments
export SELKIES_MODE="websockets"
export SELKIES_PORT=8082
export SELKIES_ADDR="127.0.0.1"
export PIXELFLUX_WAYLAND=true
export DRI_NODE=/dev/dri/renderD128
export SELKIES_USE_CPU=true

# Clean old Wayland/X11 sockets
rm -rf /tmp/.X11-unix/X1
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
rm -f /config/.XDG/wayland-1 /config/.XDG/wayland-0
rm -f /tmp/xdg-webtop/wayland-*

# Ensure XDG_RUNTIME_DIR exists
export XDG_RUNTIME_DIR=/tmp/xdg-webtop
mkdir -p $XDG_RUNTIME_DIR
chown webtop:webtop $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR

# Drop privileges and run the KDE + Selkies session under DBus
setpriv --reuid=webtop --regid=webtop --init-groups -- dbus-run-session bash -c '
    # Create config directories for webtop user
    mkdir -p $HOME/.config
    
    # Configure KWin and screen locker to disable compositing and screen lock
    /usr/bin/kwriteconfig6 --file $HOME/.config/kwinrc --group Compositing --key Enabled false
    /usr/bin/kwriteconfig6 --file $HOME/.config/kscreenlockerrc --group Daemon --key Autolock false
    
    # Start PipeWire services
    /usr/bin/pipewire &
    PIPEWIRE_PID=$!
    /usr/bin/wireplumber &
    WIREPLUMBER_PID=$!
    /usr/bin/pipewire-pulse &
    PULSE_PID=$!

    sleep 1

    # Start Selkies stream (without WAYLAND_DISPLAY since it creates wayland-1)
    /lsiopy/bin/python3 -m selkies --addr="127.0.0.1" --mode="websockets" --port="8082" &
    SELKIES_PID=$!

    # Wait for Selkies to create wayland-1
    echo "Waiting for Selkies Wayland socket wayland-1..."
    while [ ! -e "/tmp/xdg-webtop/wayland-1" ]; do
        sleep 0.1
    done
    echo "Selkies Wayland socket found. Starting KWin..."

    # Start XWayland bridge as nested Wayland compositor inside Selkies (wayland-1)
    WAYLAND_DISPLAY=wayland-1 python3 /usr/local/bin/kwin-xwayland.py &
    KWIN_PID=$!

    # Wait for KWin to create wayland-0
    echo "Waiting for KWin Wayland socket wayland-0..."
    while [ ! -e "/tmp/xdg-webtop/wayland-0" ]; do
        sleep 0.1
    done
    echo "KWin Wayland socket found."

    sleep 1

    if [ -f /usr/lib/libexec/polkit-kde-authentication-agent-1 ]; then
        /usr/lib/libexec/polkit-kde-authentication-agent-1 &
    elif [ -f /usr/libexec/polkit-kde-authentication-agent-1 ]; then
        /usr/libexec/polkit-kde-authentication-agent-1 &
    fi

    # Start Plasma Shell
    echo "Starting Plasmashell..."
    WAYLAND_DISPLAY=wayland-0 plasmashell
    
    # Clean up
    kill $KWIN_PID
    kill $SELKIES_PID
    kill $PULSE_PID
    kill $WIREPLUMBER_PID
    kill $PIPEWIRE_PID
' > /tmp/webtop.log 2>&1
