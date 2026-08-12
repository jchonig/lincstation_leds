#!/bin/sh
# Install/assert/remove logic for one packaged format. Run from the repo
# root, after `make package-<fmt>` has produced the package file there.
# Requires root and the matching distro's native package manager -- meant to
# run inside the matching container (CI matrix leg, or a local
# `docker run <image> ... make package-test-<fmt>`), not on a bare dev host.
set -eu

FMT="${1:?usage: smoketest.sh <deb|rpm|apk>}"
BINARY=/usr/sbin/lincstation_leds

assert_user() {
    getent passwd lincstation-leds >/dev/null || { echo "user lincstation-leds not created"; exit 1; }
    getent group lincstation-leds >/dev/null || { echo "group lincstation-leds not created"; exit 1; }
}

# With no real I2C hardware present (true in every CI/container environment),
# init_i2c() fails fast and main() exits 1 after logging that it couldn't
# find the LED controller. That prompt, clean failure -- not a crash, not a
# hang -- is what we assert on here; it's the correct and honest bar for an
# environment with no hardware to actually drive LEDs on.
assert_binary_runs_and_exits() {
    set +e
    timeout 5 "$BINARY" >/tmp/smoketest.out 2>&1
    ec=$?
    set -e
    if [ "$ec" -ne 1 ]; then
        echo "expected exit 1 (no I2C hardware found), got $ec"
        cat /tmp/smoketest.out
        exit 1
    fi
}

case "$FMT" in
    deb)
        pkg=$(ls ./lincstation_leds_*.deb | head -n1)
        apt-get update -qq
        apt-get install -y -qq "$pkg"
        assert_user
        assert_binary_runs_and_exits
        if command -v systemctl >/dev/null 2>&1; then
            systemctl is-enabled lincstation_leds.service
        fi
        apt-get remove -y -qq lincstation_leds
        ;;
    rpm)
        pkg=$(ls ./lincstation_leds-*.rpm | head -n1)
        dnf install -y -q "$pkg"
        assert_user
        assert_binary_runs_and_exits
        if command -v systemctl >/dev/null 2>&1; then
            systemctl is-enabled lincstation_leds.service
        fi
        dnf remove -y -q lincstation_leds
        ;;
    apk)
        pkg=$(ls ./lincstation_leds_*.apk | head -n1)
        apk add --allow-untrusted -q "$pkg"
        assert_user
        assert_binary_runs_and_exits
        apk del -q lincstation_leds
        ;;
    *)
        echo "unknown format: $FMT (expected deb, rpm, or apk)" >&2
        exit 1
        ;;
esac

echo "smoketest ($FMT): OK"
