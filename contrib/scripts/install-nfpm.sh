#!/bin/sh
# Installs a pinned version of nfpm (https://github.com/goreleaser/nfpm) as a
# static binary to /usr/local/bin/nfpm. Works identically on glibc (Ubuntu,
# Rocky) and musl (Alpine) since the release binary has no dynamic libc
# dependency. Used by CI and by local `docker run ... make package-test-*`.
set -eu

NFPM_VERSION="${NFPM_VERSION:-2.47.0}"
URL="https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -sSfL "$URL" -o "$TMPDIR/nfpm.tar.gz"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMPDIR/nfpm.tar.gz" "$URL"
else
    echo "install-nfpm.sh: need curl or wget" >&2
    exit 1
fi

tar -xzf "$TMPDIR/nfpm.tar.gz" -C "$TMPDIR" nfpm
cp "$TMPDIR/nfpm" /usr/local/bin/nfpm
chmod 0755 /usr/local/bin/nfpm

nfpm --version
