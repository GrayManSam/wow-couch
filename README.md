# wow-couch

Play **World of Warcraft: Forever** from the couch on Linux: plug the laptop into the TV and
everything switches to a controller setup automatically; unplug it and you're back at the desk
with keyboard + mouse. Built on Fedora + GNOME with WoW running through Battle.net under
GE-Proton (umu-launcher) and an Xbox controller over Bluetooth.

## What's in here

| piece | what it does |
|---|---|
| `bin/couch` + `couchmode.service` | Watches for the TV. TV plugged in -> **couch mode**: sound moves to the TV, controller desktop mode turns on, WoW gets the couch addons + graphics. Unplug -> **desk mode** restores your screens, audio and the desk addons. A screen counts as a TV if its EDID is at least 100 cm wide or its name contains "TV". |
| `bin/pad` + `padmode.service` | Drive the GNOME desktop with an Xbox controller (Bluetooth, USB or Wireless Adapter) — pointer, scroll, clicks, on-screen keyboard. Hold the Xbox button 1 s to toggle. Pauses itself while a game runs so the game gets the controller, and turns back on when the game closes. **Share** works everywhere, in game too: hold = join/leave voice, double tap = mute, triple tap = deafen (`discord-voice`). Standard library only (evdev in, uinput out). |
| `gnome-extension/pad-osk@local` | Tiny D-Bus bridge so `pad` can open GNOME's on-screen keyboard without a touchscreen. |
| `couch wow-display start\|stop` | Screens: with the TV plugged in, the TV is the only screen (4K, 200% scale, 60 Hz by default: the 3rd-gen Framework HDMI card is HDMI 2.0b and goes black at 4K120; after a 4th-gen card / HDMI 2.1 adapter put `120` in `~/.config/gameprofile/tv-max-hz`, laptop panel off) while the lid is closed, while a WoW session runs (`wow-display start`, the launcher calls it; the previous layout is saved and `stop` restores it), or after `couch on`. Lid open again -> laptop + TV come back. `--dry-run` checks layouts with `gdctl set --verify`. The service never changes the layout while WoW/Battle.net runs (Wine crashes on a monitor reconfigure). |
| `bin/battlenet` | Battle.net / WoW launcher for GE-Proton + umu, with a watchdog that cleans up the invisible "closed to tray" Battle.net session, and ends a Wow.exe left hung after the in-game **Exit Game** (client destroyed, window gone). Runs `couch wow-prep` before every launch. |
| `profiles/wow-*.cvars` | WoW graphics/gamepad CVars applied per profile before launch (render scale, vsync, FPS cap, GamePadEnable, soft targeting). |
| `addons/CouchUI` | In game: switches Edit Mode layout ("Couch"/"Desk"), chat font and UI scale by profile; `/couch arrange` moves minimap/chat/damage meter/quests out of the way; sets sensible desk keybinds once (`/couch binds undo` restores). Couch: a **Social** mini wheel on LT + RB — invite, inspect, guild invite, trade, follow, add friend, leave group, all on your current target (pick it with LB / assist; nothing is auto-targeted); your target is offered first for `/w` on Easy Controller's keyboard. `/couch social [off\|rebind]`. |
| `addons/CouchWheels` | Fills Easy Controller's radial wheels with every spell, ability and profession you know, and keeps them up to date as you learn new ones. |
| `bin/xbox-bt-tune` | One-time root script: udev rule so SDL/Proton can use the controller's hidraw node (correct layout, Guide button, rumble), and a low-latency Bluetooth LE connection interval. |
| `bin/audio` | Sound for WoW sessions: `audio wow start\|stop\|route` puts the game on the TV (unmuted, volume set — new HDMI routes start at 40%/-24 dB otherwise), optional EasyEffects presets; `audio wow doctor` prints the whole chain and plays 3 test beeps through the TV. |
| `bin/xbox-headset` + `xbox-headset.service` | Headset in the controller's 3.5 mm jack -> sound on **TV + headset** at once (like an Xbox), headset mic becomes the default input. Switches automatically by connection: Bluetooth = TV only (the jack never carries audio over Bluetooth), USB-C or Xbox Wireless Adapter = TV + headset (needs the `xone` driver). `audio headset status\|test\|chat-only on\|off\|mute\|mirror tv\|never`. |
| `headset/install-xone.sh` | One-time root script: installs [xone](https://github.com/dlundqvist/xone) v0.5.8 with DKMS (Secure Boot: uses the enrolled DKMS key) + the Wireless Adapter firmware. xpad is only loaded when xone isn't built for the running kernel, so a kernel update xone can't build for never leaves a USB controller without a driver. `--uninstall` undoes it. |
| `bin/discord-voice` | Join / leave / mute / deafen a Discord voice channel from the controller, via Discord's local RPC as **your own** Discord application (no user token, no self-bot). `discord-voice setup` once. |
| `bin/discord-overlay` + `autostart/` | Starts [Discover Overlay](https://github.com/trigg/Discover) (Flatpak `io.github.trigg.discover_overlay`) — who's in voice / speaking, over the game; Discord's own overlay doesn't run on Linux. |

Per profile, `couch wow-prep` toggles addons in every character's `AddOns.txt`:

- couch: Easy Controller + CouchWheels
- desk: Bartender4
- always: CouchUI (+ CouchLights from [govee-wow](https://github.com/GrayManSam/govee-wow) if installed)
- never: ConsolePort (it taints Forever's own gamepad UI: "execution tainted by 'ConsolePort'")

`Config.wtf` keeps its CRLF line endings when edited.

## Requirements

- Fedora / any distro with GNOME 49 (Mutter `gdctl`), PipeWire (`pactl`), Python 3.11+.
- WoW: Forever via Battle.net under GE-Proton + umu-launcher (paths are variables at the top of
  `bin/battlenet`). Default game folder:
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_` — set `WOW_DIR`
  if yours differs.
- Addons from CurseForge/Wago: **Easy Controller** (couch), **Bartender4** (desk).
- Your user needs access to `/dev/uinput` and the controller's event device for `pad`
  (input group or a udev rule).

## Install

```sh
git clone https://github.com/GrayManSam/wow-couch
cd wow-couch
WOW_DIR="/path/to/World of Warcraft/_forever_" ./install.sh    # WOW_DIR optional
sudo ~/.local/bin/xbox-bt-tune                                  # optional, once
```

Log out and back in once so GNOME loads the on-screen-keyboard extension.

## Use

```
couch                 current profile + connected screens
couch on | off        force couch / desk now;  couch auto  = follow the TV again
couch wow-display start|stop [--dry-run]   TV only while WoW runs, previous layout after
pad                   toggle controller desktop mode (or hold the Xbox button 1 s)
pad keys              button map
battlenet --wow       launch straight into WoW Forever
/couch                in game: status and commands (font, scale, layout, arrange, binds)
```

Tune per-machine values at the top of the scripts: the laptop panel mode in `couch`
(`LAPTOP_MODE`), pointer speed / dead zone in `pad`, the games that pause `pad` in
`~/.config/padmode/games`.

## Headset and Discord

```
sudo ./headset/install-xone.sh     # once, controller on USB-C (or Wireless Adapter) — headset jack audio
audio headset test                 # beeps in the headset + mic level check
echo 'My Server' > ~/.config/discord-voice/server
discord-voice setup                # once: your Discord app's client ID + secret, then Authorize
flatpak install --user flathub io.github.trigg.discover_overlay   # voice overlay
```

`discord-voice` uses Discord's RPC voice scopes, which Discord only grants to the application's
owner / team members without review — use an application you own (Developer Portal -> OAuth2:
add redirect `http://127.0.0.1`). Bluetooth audio devices that `audio` reconnects go in
`~/.config/wow-audio/bt-devices` (one MAC per line).

## License

MIT. World of Warcraft is a trademark of Blizzard Entertainment. This project is not
affiliated with or endorsed by Blizzard, Microsoft, or the Easy Controller / Bartender4
authors; their addons are not included here.
