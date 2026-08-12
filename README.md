# lincstation_leds
Daemon to set the Lincstation N2 LEDs on Linux other than Unraid

The Lincstation N2 is a fine all-flash NAS. It uses mostly standard PC
hardware, which means you can run your own OS on top of it instead of
proprietary ones like QNAP's QuTS Hero or Synology's whatever (if you weren't
deterred by Synology's abbhorent moves to force you to buy their marked-up
hard drives).

I installed Alpine Linux on mine. Unfortunately, if you do not use the
supplied freemium Unraid software, the LEDs will blink continuously, which is
particularly annoying in my case because they are in my peripheral vision.

Lincstation supplies a closed-source daemon with its Unraid distribution on a
USB stick (I removed mine), apparently written in Go but quite inefficient
because it makes the necessary I2C/SMBus calls to the LEDs by forking to the
i2c-tools utility `i2cset`. Github user ffalt reverse-engineered the protocol
in [this gist](https://gist.github.com/ffalt/984aa3644a90d4230eaf5b129aaf1eeb).

I asked the Anthropic Claude Sonnet 4 LLM to help me write a daemon written in
C to manage the LEDs:
https://claude.ai/public/artifacts/cc0feaf6-524f-431b-b1e8-505ad07f75f3

Claude did a surprisingly decent job of writing the boilerplate, you can see
in the Git history the changes I did to make it work properly, including
subtle bugs around handling rollover or incorrectly thinking disk I/O
utilization is 100% when no disk writes occurred.

I have only tested this on Alpine Linux but there is no reason it shouldn't
work on other flavors of Linux (you may need to make changes for systemd,
though).

To build, simply run `make`. You will need to have the packages `i2c-tools`
and `i2c-tools-dev` (and optionally `i2c-tools-doc`) installed.

## Installing a prebuilt package

Prebuilt `.deb` (Debian/Ubuntu), `.rpm` (Fedora/RHEL/Rocky/Alma), and `.apk`
(Alpine) packages are built by CI for every tagged release, each installing
a systemd unit (deb/rpm) or OpenRC init script (apk) plus the udev/mdev rules
needed to grant a dedicated `lincstation-leds` system user access to the I2C
device. See the [Releases](https://github.com/jchonig/lincstation_leds/releases)
page, or the GitHub Pages-hosted APT/YUM/APK repositories for direct
`apt install` / `dnf install` / `apk add` access.

## Development

Contributors should run `make install-hooks` once after cloning — this wires
up a pre-commit hook (`make test`) that catches build breakage before it's
committed. `make test` alone is fast and needs no Docker; the full per-distro
package build/install checks (`make package-test-deb`, `-rpm`, `-apk`) need
Docker/root and the target distro's package manager, and are what CI runs on
every push and PR.

## Release signing setup (maintainers only)

Before `.github/workflows/release.yml` can publish the signed APT/YUM/APK
repositories to GitHub Pages, two repo secrets need to exist:
`GPG_SIGNING_KEY` and `ALPINE_SIGNING_KEY`. These are the trust root that
everyone installing from the published repos relies on, so generate them
yourself, on your own machine — don't generate a code-signing key in CI or
hand it to a third party to generate for you, even momentarily.

### GPG key (signs the APT and YUM repos)

Use a distinct UID (via a comment) rather than your everyday
`Jeffrey C Honig <jch@honig.net>` identity — you don't want your personal
GPG key (the one used for e.g. git commit signing) sitting in a GitHub
Actions secret, reachable by every workflow run and every third-party
Action they pull in. Keeping this key purpose-built and separate means a
compromise here only costs you package-signing trust for this repo, not
your real identity:

```
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "Jeffrey C Honig (lincstation_leds CI signing) <jch@honig.net>" \
    default default never

gpg --export-secret-keys --armor "Jeffrey C Honig (lincstation_leds CI signing) <jch@honig.net>" \
    | gh secret set GPG_SIGNING_KEY --repo jchonig/lincstation_leds
```

(If a key under that exact UID already exists, `--quick-generate-key` will
refuse with "a key ... already exists" — that's gpg protecting you from
silently reusing an existing identity's key. Check `gpg --list-secret-keys`
first if you're unsure.)

Generated without a passphrase on purpose: this key only ever runs
unattended in CI, and the GitHub secret itself is the protection boundary
(anyone who can read repo secrets could read a passphrase stored alongside
it too, so a passphrase adds no real protection here). The release workflow
derives the key's fingerprint at sign time — no separate fingerprint secret
needed.

### Alpine (abuild) key (signs the APK repo)

Alpine's `apk index` signing scheme is just a plain RSA keypair — nothing
Alpine-specific about the key itself, only about how `abuild-sign` embeds
the signature into `APKINDEX.tar.gz`. `abuild-keygen` (part of Alpine's
`alpine-sdk`) is the usual way to generate one, but it isn't available
outside Alpine; `openssl`, which is, produces an equivalent key directly:

```
openssl genrsa -out lincstation_leds.rsa 4096
gh secret set ALPINE_SIGNING_KEY --repo jchonig/lincstation_leds \
    < lincstation_leds.rsa
rm lincstation_leds.rsa
```

(If you do have `abuild-keygen` available — e.g. inside an Alpine
container — `abuild-keygen -a -n lincstation_leds` works too and produces
the same kind of key at `~/.abuild/lincstation_leds.rsa`.)

You don't need to generate or upload the public half yourself either way;
`release.yml` derives it from the private key at publish time
(`openssl rsa -pubout`) and republishes it under the deployed `apk/` tree
for users to drop into `/etc/apk/keys/`.

Before the first release, also enable GitHub Pages for this repo: **Settings →
Pages → Build and deployment → Source: Deploy from a branch → Branch:
`gh-pages`**. `peaceiris/actions-gh-pages` creates and pushes the `gh-pages`
branch itself on first run, but it won't flip the Pages setting on for
you — that branch has to exist *before* you can select it in the UI, so
this is a one-time step to do *after* the first successful `release.yml`
run (which creates the branch) but before you consider the repos actually
published/reachable.

Once both secrets exist, push a `v*` tag to trigger a real release.

You can activate debug output on stdout by calling:

```
env LEDS_DEBUG=true lincstation_leds
```

By default, it will update the LEDs once per second. If you want something
more real-time, you can change `ACTIVITY_SAMPLE_INTERVAL` in the code to
something shorter. Just be aware that at 10 Hz, it consumes 2–3% CPU on mine.
