# wow-couch

Play **World of Warcraft: Forever** from the couch on Linux: plug the laptop into the TV and
everything switches to a controller setup automatically; unplug it and you're back at the desk
with keyboard + mouse. Built on Fedora + GNOME with WoW running through Battle.net under
GE-Proton (umu-launcher) and an Xbox controller over Bluetooth.

## What's in here

| piece | what it does |
|---|---|
| `bin/couch` + `couchmode.service` | Watches for the TV. TV plugged in -> **couch mode**: TV becomes the only screen (4K, 200% scale, highest refresh it offers up to 120 Hz), sound moves to the TV, controller desktop mode turns on, WoW gets the couch addons + graphics. Unplug -> **desk mode** restores your screens, audio and the desk addons. A screen counts as a TV if its EDID is at least 100 cm wide or its name contains "TV". |
| `bin/pad` + `padmode.service` | Drive the GNOME desktop with an Xbox controller (pointer, scroll, clicks, on-screen keyboard). Hold the Xbox button 1 s to toggle. Pauses itself while a game runs so the game gets the controller. Standard library only (evdev in, uinput out). |
| `gnome-extension/pad-osk@local` | Tiny D-Bus bridge so `pad` can open GNOME's on-screen keyboard without a touchscreen. |
| `bin/battlenet` | Battle.net / WoW launcher for GE-Proton + umu, with a watchdog that cleans up the invisible "closed to tray" Battle.net session. Runs `couch wow-prep` before every launch. |
| `profiles/wow-*.cvars` | WoW graphics/gamepad CVars applied per profile before launch (render scale, vsync, FPS cap, GamePadEnable, soft targeting). |
| `addons/CouchUI` | In game: switches Edit Mode layout ("Couch"/"Desk"), chat font and UI scale by profile; `/couch arrange` moves minimap/chat/damage meter/quests out of the way; sets sensible desk keybinds once (`/couch binds undo` restores). |
| `addons/CouchWheels` | Fills Easy Controller's radial wheels with every spell, ability and profession you know, and keeps them up to date as you learn new ones. |
| `bin/xbox-bt-tune` | One-time root script: udev rule so SDL/Proton can use the controller's hidraw node (correct layout, Guide button, rumble), and a low-latency Bluetooth LE connection interval. |

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
pad                   toggle controller desktop mode (or hold the Xbox button 1 s)
pad keys              button map
battlenet --wow       launch straight into WoW Forever
/couch                in game: status and commands (font, scale, layout, arrange, binds)
```

Tune per-machine values at the top of the scripts: the laptop panel mode in `couch`
(`LAPTOP_MODE`), pointer speed / dead zone in `pad`, the games that pause `pad` in
`~/.config/padmode/games`.

## License

MIT. World of Warcraft is a trademark of Blizzard Entertainment. This project is not
affiliated with or endorsed by Blizzard, Microsoft, or the Easy Controller / Bartender4
authors; their addons are not included here.
