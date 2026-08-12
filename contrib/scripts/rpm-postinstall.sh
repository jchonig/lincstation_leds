#!/bin/sh
set -e

if ! getent group lincstation-leds >/dev/null; then
    groupadd --system lincstation-leds
fi
if ! getent passwd lincstation-leds >/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin \
        --gid lincstation-leds lincstation-leds
fi

# Reload udev rules and re-trigger so any already-present i2c nodes pick up
# the new group ownership without a reboot.
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || true
    udevadm trigger --subsystem-match=i2c-dev || true
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl enable --now lincstation_leds.service || true
fi

exit 0
