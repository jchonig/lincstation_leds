TARGET = lincstation_leds
CC = gcc
CFLAGS = -O2
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo 0.0.0-dev)

.PHONY: all test package-deb package-rpm package-apk \
	smoketest-deb smoketest-rpm smoketest-apk \
	package-test-deb package-test-rpm package-test-apk \
	install-hooks clean

all: lincstation_leds

lincstation_leds: lincstation_leds.c
	$(CC) $(CFLAGS) -o $@ $^ -li2c

# Fast, no Docker/root/network needed -- safe to run on every commit (this is
# what the pre-commit hook installed by `make install-hooks` runs). With no
# real I2C hardware present (true on any dev machine or CI runner),
# init_i2c() fails fast and main() exits 1 after logging that it couldn't
# find the LED controller -- that prompt, clean failure is what's asserted.
test: lincstation_leds
	@./lincstation_leds >/tmp/leds-test.out 2>&1; ec=$$?; \
	  if [ $$ec -ne 1 ]; then echo "expected exit 1, got $$ec"; cat /tmp/leds-test.out; exit 1; fi
	@LEDS_DEBUG=true ./lincstation_leds 2>&1 | grep -q "Disk & Network Activity Monitor" \
	  || { echo "LEDS_DEBUG output missing"; exit 1; }
	@echo "test: OK"

# One target per package format: build with nfpm (must be on PATH -- see
# contrib/scripts/install-nfpm.sh), install it via the distro's native
# package manager, assert user/files/exit-behavior, then remove it again.
# Requires root and the matching distro's package manager, so these are
# meant to run inside the matching container (CI matrix leg, or a local
# `docker run <image> ... make package-test-<fmt>`), never bare on a dev host.
package-deb package-rpm package-apk: package-%: all
	VERSION="$(VERSION)" nfpm package --config packaging/nfpm.yaml --packager $* --target .

smoketest-deb smoketest-rpm smoketest-apk: smoketest-%:
	contrib/scripts/smoketest.sh $*

package-test-deb: package-deb smoketest-deb
package-test-rpm: package-rpm smoketest-rpm
package-test-apk: package-apk smoketest-apk

# One-time per clone: makes `git commit` run `make test` first via
# contrib/git-hooks/pre-commit (git hooks aren't versioned/auto-installed).
install-hooks:
	git config core.hooksPath contrib/git-hooks

clean:
	-rm -f $(TARGET) *~ *.deb *.rpm *.apk
