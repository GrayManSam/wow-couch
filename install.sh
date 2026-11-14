#!/usr/bin/env bash
# Installs wow-couch for the current user: scripts, profiles, addons, GNOME extension, services.
set -euo pipefail
cd "$(dirname "$0")"
DEFAULT_WOW="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_"
WOW_DIR="${WOW_DIR:-$DEFAULT_WOW}"

for f in couch pad battlenet xbox-bt-tune audio xbox-headset discord-voice discord-overlay; do
  install -Dm755 "bin/$f" "$HOME/.local/bin/$f"
done

mkdir -p "$HOME/.config/gameprofile"
for f in profiles/*.cvars; do
  cp -n "$f" "$HOME/.config/gameprofile/" || true      # keep your own tuning if present
done

if [[ -d "$WOW_DIR/Interface/AddOns" ]]; then
  cp -r addons/CouchUI addons/CouchWheels "$WOW_DIR/Interface/AddOns/"
  echo "CouchUI + CouchWheels -> $WOW_DIR/Interface/AddOns"
else
  echo "WoW AddOns folder not found at: $WOW_DIR/Interface/AddOns"
  echo "  copy addons/* there yourself, or rerun with WOW_DIR=/path/to/_forever_"
fi

EXT="$HOME/.local/share/gnome-shell/extensions"
mkdir -p "$EXT"
cp -r gnome-extension/pad-osk@local "$EXT/"
gnome-extensions enable pad-osk@local 2>/dev/null || echo "enable pad-osk@local after logging back in"

mkdir -p "$HOME/.config/systemd/user"
cp systemd/padmode.service systemd/couchmode.service systemd/xbox-headset.service "$HOME/.config/systemd/user/"
mkdir -p "$HOME/.config/autostart"
sed "s|@HOME@|$HOME|" autostart/discord-overlay.desktop > "$HOME/.config/autostart/discord-overlay.desktop"
if [[ "$WOW_DIR" != "$DEFAULT_WOW" ]]; then
  mkdir -p "$HOME/.config/systemd/user/couchmode.service.d"
  printf '[Service]\nEnvironment="WOW_DIR=%s"\n' "$WOW_DIR" \
    > "$HOME/.config/systemd/user/couchmode.service.d/wow-dir.conf"
fi
systemctl --user daemon-reload
systemctl --user enable --now padmode.service couchmode.service xbox-headset.service
echo "Installed. Install Easy Controller + Bartender4 in WoW, then log out/in once for the OSK extension."
echo "Headset jack (USB-C / Wireless Adapter): sudo ./headset/install-xone.sh   Discord voice: see README."
