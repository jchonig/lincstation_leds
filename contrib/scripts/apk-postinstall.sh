#!/bin/sh
# busybox ash-compatible -- no bashisms
set -e

if ! getent group lincstation-leds >/dev/null 2>&1; then
    addgroup -S lincstation-leds
fi
if ! getent passwd lincstation-leds >/dev/null 2>&1; then
    adduser -S -D -H -h /nonexistent -s /sbin/nologin \
        -G lincstation-leds lincstation-leds
fi

# Splice the mdev fragment into /etc/mdev.conf if not already present.
FRAGMENT=/usr/share/lincstation_leds/mdev.conf.fragment
if [ -f "$FRAGMENT" ] && [ -f /etc/mdev.conf ] && \
   ! grep -qF "lincstation-leds" /etc/mdev.conf; then
    cat "$FRAGMENT" >> /etc/mdev.conf
fi

if command -v rc-update >/dev/null 2>&1; then
    rc-update add lincstation_leds default || true
    rc-service lincstation_leds start || true
fi

exit 0
