#!/usr/bin/env python3
"""Point selkies-session's desktop at the systemd user bus.

selkies 2.0.0's session.py strips DBUS_SESSION_BUS_ADDRESS out of the desktop
environment (HOST_SESSION_VARS) and then unconditionally wraps the session in
`dbus-run-session`. Plasma therefore lands on a *private* session bus that has no
org.freedesktop.systemd1 behind it, so KDE's systemd-activated portal backend
(plasma-xdg-desktop-portal-kde, whose D-Bus service declares SystemdService=)
never starts and the session stalls before ksmserver/plasmashell.

Keep the advertised address, and only spawn a private bus when there is not one
already — that way the desktop connects to the bus owned by user@1000.service.

Run at image build time against the venv installed by the Selkies layer.
"""
import glob
import sys

matches = glob.glob("/opt/selkies/lib/python*/site-packages/selkies/session.py")
if not matches:
    sys.exit("selkies session.py not found under /opt/selkies")

path = matches[0]
with open(path, "r") as fh:
    src = fh.read()

hunks = [
    # Do not scrub the session bus address from the desktop environment.
    (
        '"XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",\n',
        '"XAUTHORITY",\n',
    ),
    # Only wrap in a private bus when no session bus is advertised.
    (
        '        bus = ["dbus-run-session", "--"] if shutil.which("dbus-run-session") else []\n',
        '        # Prefer an already-advertised session bus (the systemd user manager owns\n'
        '        # $XDG_RUNTIME_DIR/bus). Only spawn a private bus when none is available;\n'
        '        # on a private bus the KDE portal backend cannot be systemd-activated.\n'
        '        bus = [] if env.get("DBUS_SESSION_BUS_ADDRESS") else (["dbus-run-session", "--"] if shutil.which("dbus-run-session") else [])\n',
    ),
]

for old, new in hunks:
    if old not in src:
        sys.exit("patch target not found in %s: %r" % (path, old))
    src = src.replace(old, new)

with open(path, "w") as fh:
    fh.write(src)

print("patched %s" % path)
