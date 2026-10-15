#!/bin/sh
set -e
FACTORY=/usr/share/factory/etc
OVERLAY=/var/lib/etc-overlay
if [ ! -d "$OVERLAY" ]; then mkdir -p "$OVERLAY"; fi
if [ -z "$(ls -A "$OVERLAY" 2>/dev/null)" ] && [ -d "$FACTORY" ]; then
  cp -a "$FACTORY"/. "$OVERLAY"/
fi
if [ -d "$OVERLAY" ] && [ "$(ls -A "$OVERLAY" 2>/dev/null)" ]; then
  cp -a "$OVERLAY"/. /etc/
fi
