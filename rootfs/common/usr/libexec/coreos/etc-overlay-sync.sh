#!/bin/sh
set -e
FACTORY=/usr/share/factory/etc
OVERLAY=/var/lib/etc-overlay

# Runtime-owned paths under /etc. systemd, the container runtime (podman) and
# NetworkManager regenerate these on every boot; restoring a stale copy from the
# factory snapshot over them breaks the running system — a re-zeroed
# /etc/machine-id kills user@UID.service and every D-Bus session bus that needs
# a machine id. Keep this list in sync with the factory-snapshot cleanup in the
# base Containerfile.
RUNTIME_OWNED="machine-id machine-info hostname resolv.conf"

if [ ! -d "$OVERLAY" ]; then mkdir -p "$OVERLAY"; fi
if [ -z "$(ls -A "$OVERLAY" 2>/dev/null)" ] && [ -d "$FACTORY" ]; then
  cp -a "$FACTORY"/. "$OVERLAY"/
fi
# Drop any runtime-owned file the seed may have carried in (and clean up stale
# ones left in a persisted overlay from a pre-fix image) so they are never
# copied back over /etc.
for f in $RUNTIME_OWNED; do rm -f "$OVERLAY/$f"; done
if [ -d "$OVERLAY" ] && [ "$(ls -A "$OVERLAY" 2>/dev/null)" ]; then
  cp -a "$OVERLAY"/. /etc/
fi
