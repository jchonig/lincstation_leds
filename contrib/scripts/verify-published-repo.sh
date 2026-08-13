#!/bin/sh
# Installs lincstation-leds from the REAL, currently-published, signed repo
# at $PAGES_BASE -- not a locally-built file. This is the only thing that
# catches bugs in what actually got published (index/filename mismatches,
# key-format issues, propagation problems) rather than in the build itself;
# a locally-built-file smoketest (see smoketest.sh) can't see those.
set -eu

FMT="${1:?usage: verify-published-repo.sh <deb|rpm|apk>}"
BASE="${PAGES_BASE:?PAGES_BASE env var required}"

# GitHub Pages can take a little while to actually serve a just-deployed
# commit, so wait for the real content to go live before trying to install
# from it -- otherwise this would flake on a fresh CDN cache miss.
wait_for_url() {
    url="$1"
    i=0
    while [ "$i" -lt 30 ]; do
        code=$(curl -sS --max-time 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo 000)
        if [ "$code" = "200" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 5
    done
    echo "timed out waiting for $url to return 200 (last: $code)" >&2
    return 1
}

# The index/repodata being live (wait_for_url, above) doesn't guarantee
# every individual package file behind it has also finished propagating --
# each release re-signs the *entire* accumulated set of historical
# packages, so even an "unchanged" old version's file content actually
# changes on every release, and GitHub Pages' CDN doesn't invalidate every
# file atomically. A freshly-generated index checksum can transiently
# mismatch a not-yet-propagated package file for a short window after
# deploy. Retry the actual install through that window rather than failing
# on what's usually just a few seconds of CDN lag.
retry() {
    n=0
    max=6
    while [ "$n" -lt "$max" ]; do
        if "$@"; then
            return 0
        fi
        n=$((n + 1))
        echo "attempt $n/$max failed, retrying in 15s..." >&2
        sleep 15
    done
    return 1
}

case "$FMT" in
    deb)
        wait_for_url "$BASE/apt/dists/stable/InRelease"
        apt-get update -qq
        apt-get install -y -qq gnupg
        curl -fsSL "$BASE/apt/lincstation-leds.gpg" -o /usr/share/keyrings/lincstation-leds.gpg
        echo "deb [signed-by=/usr/share/keyrings/lincstation-leds.gpg] $BASE/apt stable main" \
            > /etc/apt/sources.list.d/lincstation-leds.list
        apt-get update -qq
        retry apt-get install -y -qq lincstation-leds
        dpkg -s lincstation-leds >/dev/null
        getent passwd lincstation-leds >/dev/null
        apt-get remove -y -qq lincstation-leds
        ;;
    rpm)
        wait_for_url "$BASE/yum/repodata/repomd.xml"
        cat > /etc/yum.repos.d/lincstation-leds.repo <<REPO
[lincstation-leds]
name=lincstation_leds
baseurl=$BASE/yum/
enabled=1
gpgcheck=1
gpgkey=$BASE/yum/RPM-GPG-KEY-lincstation_leds
REPO
        retry dnf install -y lincstation-leds
        rpm -q lincstation-leds >/dev/null
        getent passwd lincstation-leds >/dev/null
        dnf remove -y lincstation-leds
        ;;
    apk)
        wait_for_url "$BASE/apk/x86_64/APKINDEX.tar.gz"
        wget -q -O /etc/apk/keys/lincstation_leds.rsa.pub "$BASE/apk/lincstation_leds.rsa.pub"
        grep -qF "$BASE/apk" /etc/apk/repositories || echo "$BASE/apk" >> /etc/apk/repositories
        apk update
        retry apk add lincstation-leds
        apk info -e lincstation-leds >/dev/null
        getent passwd lincstation-leds >/dev/null
        apk del lincstation-leds
        ;;
    *)
        echo "unknown format: $FMT (expected deb, rpm, or apk)" >&2
        exit 1
        ;;
esac

echo "verify-published-repo ($FMT): OK"
