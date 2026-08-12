#!/bin/sh
# busybox ash-compatible -- no bashisms
set -e

if command -v rc-service >/dev/null 2>&1; then
    rc-service lincstation_leds stop || true
    rc-update del lincstation_leds default || true
fi

exit 0
