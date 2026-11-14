#!/usr/bin/env bash
# Install the xone driver (dlundqvist/xone v0.5.8) so the Xbox controller's 3.5mm headset jack
# works on Linux over USB-C and over the Xbox Wireless Adapter. Bluetooth never carries jack audio.
#
#   Run once:      sudo ~/Games/headset/install-xone.sh
#   Undo:          sudo ~/Games/headset/install-xone.sh --uninstall
#
# What it does (nothing else):
#   1. checks: root, Secure Boot key (DKMS key already enrolled in MOK -> no reboot / MOK screen),
#      dkms + kernel-devel for the running kernel, source = git tag v0.5.8 (commit f2aa9fe011)
#   2. xone's own install.sh: DKMS build + install (signed with /var/lib/dkms/mok.key),
#      /etc/modprobe.d/xone-blacklist.conf (blacklists xpad + mt76x2u), unloads xpad
#   3. xone's install/firmware.sh: Xbox Wireless Adapter firmware into /lib/firmware
#      (downloaded from Microsoft Update; Microsoft Terms of Use apply) — only needed for the dongle
#   4. loads the modules, verifies the signature, waits for the controller to re-appear
# Bluetooth (hid-microsoft) is not touched. Your Bluetooth pairing stays as it is.
set -euo pipefail

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/xone
WANT_COMMIT=f2aa9fe01103d7600553b505b298ff0bd47ff280
KVER=$(uname -r)
say()  { printf '\n== %s\n' "$*"; }
die()  { printf '\n!! %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo:  sudo $0"
USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] || die "run through sudo from your own account (needs SUDO_USER)"
if [ ! -d "$SRC/.git" ]; then          # fresh install from the repo: fetch the pinned release
  sudo -u "$USER_NAME" git clone --quiet --branch v0.5.8 https://github.com/dlundqvist/xone "$SRC" \
    || die "couldn't download xone into $SRC"
fi
cd "$SRC" || die "source missing: $SRC"

if [ "${1:-}" = --uninstall ]; then
  say "Removing xone (driver, blacklist, dongle firmware)"
  ./uninstall.sh
  modprobe xpad 2>/dev/null || true
  say "Done. Unplug/replug the USB cable so xpad takes the controller again."
  exit 0
fi

say "Checks"
got=$(sudo -u "$USER_NAME" git -C "$SRC" rev-parse HEAD)
[ "$got" = "$WANT_COMMIT" ] || die "source is not xone v0.5.8 ($got)"
sudo -u "$USER_NAME" git -C "$SRC" diff --quiet HEAD || die "source tree has local changes"
command -v dkms >/dev/null || die "dkms missing (dnf install dkms)"
[ -d "/lib/modules/$KVER/build" ] || die "kernel-devel for $KVER missing (dnf install kernel-devel-$KVER)"
for t in git curl bsdtar sha256sum; do command -v $t >/dev/null || die "$t missing"; done
if mokutil --sb-state 2>/dev/null | grep -q enabled; then
  [ -r /var/lib/dkms/mok.pub ] || die "Secure Boot on but no DKMS key (/var/lib/dkms/mok.pub)"
  # mokutil --test-key exits non-zero even when the key IS enrolled: read its text, not its status
  keytest=$(mokutil --test-key /var/lib/dkms/mok.pub 2>&1 || true)
  grep -q 'already enrolled' <<<"$keytest" \
    || die "DKMS key not enrolled: run  sudo mokutil --import /var/lib/dkms/mok.pub , reboot, Enroll MOK, then re-run"
  echo "   Secure Boot on; DKMS signing key is enrolled -> modules will load, no reboot needed"
fi
case "$KVER" in 7.[4-9]*|[89].*)
  echo "   WARNING: kernel $KVER — xone v0.5.8 does not build on 7.4+ yet (upstream issue #237)";;
esac
echo "   kernel $KVER, source v0.5.8 ok"

say "Building + installing xone with DKMS (about 1 minute)"
./install.sh

say "Kernel-update safety: xpad comes back by itself when xone isn't built for the running kernel"
# xone's file blacklists xpad for every kernel. If a kernel update (e.g. 7.4, xone issue #237)
# can't build xone, that would leave a USB controller with no driver at all. Instead: xpad loads
# only when no xone_wired module exists for the running kernel.
cat > /etc/modprobe.d/xone-blacklist.conf <<'EOF'
# Written by ~/Games/headset/install-xone.sh (replaces xone's plain "blacklist xpad")
install xpad /bin/sh -c 'modinfo -k "$(uname -r)" xone_wired >/dev/null 2>&1 || exec /usr/sbin/modprobe --ignore-install xpad $CMDLINE_OPTS'
blacklist mt76x2u
EOF
echo "   /etc/modprobe.d/xone-blacklist.conf: xpad only if xone_wired is missing for the kernel"

say "Dongle firmware (Xbox Wireless Adapter; Microsoft Terms of Use: https://www.microsoft.com/en-us/legal/terms-of-use)"
./install/firmware.sh --skip-disclaimer

say "Loading modules"
modprobe -r xpad 2>/dev/null || true
for m in xone_wired xone_dongle xone_gip_gamepad xone_gip_headset; do modprobe "$m"; done
signer=$(modinfo -F signer xone_gip_headset 2>/dev/null || true)
echo "   xone_gip_headset signer: ${signer:-none}"
lsmod | grep -E '^xone_' | awk '{print "   loaded: " $1}'

say "Re-attaching a USB-connected controller"
for d in /sys/bus/usb/devices/*; do
  [ "$(cat "$d/idVendor" 2>/dev/null)" = 045e ] || continue
  p=$(cat "$d/idProduct"); case "$p" in 02fe|02e6|02f9|091e) kind=adapter;; *) kind=controller;; esac
  echo "   $kind 045e:$p at ${d##*/}: re-binding"
  echo 0 > "$d/authorized"; sleep 1; echo 1 > "$d/authorized"
done

say "Waiting up to 20 s for the headset sound card (headset must be in the controller jack)"
for _ in $(seq 20); do grep -q 'Xbox Headset' /proc/asound/cards && break; sleep 1; done
if grep -q 'Xbox Headset' /proc/asound/cards; then
  grep -A1 'Xbox Headset' /proc/asound/cards | sed 's/^/   /'
  echo "   OK — the headset is a sound card now. Check with:  audio headset status"
else
  echo "   No headset card yet. Unplug + replug the USB cable (or the headset), then:  audio headset status"
fi
echo
echo "Done. Bluetooth is unchanged; jack audio works only over USB-C or the Xbox Wireless Adapter."
