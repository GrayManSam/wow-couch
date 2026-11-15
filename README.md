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
| on-screen keyboard | With the [GJS OSK](https://extensions.gnome.org/extension/5949/gjs-osk/) GNOME extension installed (`gjsosk@vishram1123.com`), `pad` uses it instead of GNOME's docked keyboard: **Y** opens / closes it, it opens by itself when you click a text field (only while the controller drives the desktop), and **View + right-stick click** moves it to its next spot (bottom, top, the corners, middle). Without the extension `pad` falls back to GNOME's own keyboard. |
| `gnome-extension/pad-osk@local` | Tiny D-Bus bridge so `pad` can open GNOME's on-screen keyboard without a touchscreen. |
| `couch wow-display start\|stop` | Screens: with the TV plugged in, the TV is the only screen (4K, 200% scale, 60 Hz by default: the 3rd-gen Framework HDMI card is HDMI 2.0b and goes black at 4K120; after a 4th-gen card / HDMI 2.1 adapter put `120` in `~/.config/gameprofile/tv-max-hz`, laptop panel off) while the lid is closed, while a WoW session runs (`wow-display start`, the launcher calls it; the previous layout is saved and `stop` restores it), or after `couch on`. Lid open again -> laptop + TV come back. `--dry-run` checks layouts with `gdctl set --verify`. The service never changes the layout while WoW/Battle.net runs (Wine crashes on a monitor reconfigure). |
| `bin/battlenet` | Battle.net / WoW launcher for GE-Proton + umu, with a watchdog that cleans up the invisible "closed to tray" Battle.net session, and ends a Wow.exe left hung after the in-game **Exit Game** (client destroyed, window gone). Runs `couch wow-prep` before every launch. |
| `profiles/wow-*.cvars` | WoW graphics/gamepad CVars applied per profile before launch (render scale, vsync, FPS cap, GamePadEnable, soft targeting). |
| `addons/CouchUI` | In game: switches Edit Mode layout ("Couch"/"Desk"), chat font and UI scale by profile; `/couch arrange` moves minimap/chat/damage meter/quests out of the way; sets sensible desk keybinds once (`/couch binds undo` restores). Couch: a **Social** mini wheel on LT + RT + D-pad left — invite, inspect, the target's menu, trade, follow, add friend, leave group, all on your current target (pick it with LB / assist); your target is offered first for `/w` on Easy Controller's keyboard. `/couch social [off\|rebind]`. (RB alone stays the game's enemy targeting: Easy Controller can only read LT + RB if RB alone is taken from the game.) **Hunter** macros (Fight, Panic potion, pet, stings, mark...) replace their spells on your buttons and wheels, plus a Hunter wheel and an **Emote** wheel. **Recruit** (LT + D-pad right): targets the nearest player of your faction with no guild (or keeps your own target) and invites them — see *Guild invites* below. **Quest item** button: the usable item of your current quest (the one you just looted, else the nearest quest's) on one empty controller button, `/couch questitem`. **Auto bag sort**: the game's own Clean Up Bags runs when you close your bags after something changed (never in a fight or at a vendor / bank / mailbox), `/couch sort on\|off\|now`. Logs any action WoW blocks (chat + `CouchUIDB.blocked`). **`/couch help`** (or *Controls* on the Social wheel) shows the controller map: every button in every layer read live from Easy Controller, the wheels, what each macro does, and the music / voice shortcuts; macro buttons say what they do in their tooltip. |
| `addons/CouchWheels` | Fills Easy Controller's radial wheels with every spell, ability and profession you know, and keeps them up to date as you learn new ones. |
| `bin/xbox-bt-tune` | One-time root script: udev rule so SDL/Proton can use the controller's hidraw node (correct layout, Guide button, rumble), and a low-latency Bluetooth LE connection interval. |
| `bin/audio` | Sound for WoW sessions: `audio wow start\|stop\|route` puts the game on the TV (unmuted, volume set — new HDMI routes start at 40%/-24 dB otherwise), optional EasyEffects presets; `audio wow doctor` prints the whole chain and plays 3 test beeps through the TV. |
| `bin/xbox-headset` + `xbox-headset.service` | Headset in the controller's 3.5 mm jack -> sound on **TV + headset** at once (like an Xbox), headset mic becomes the default input. Switches automatically by connection: Bluetooth = TV only (the jack never carries audio over Bluetooth), USB-C or Xbox Wireless Adapter = TV + headset (needs the `xone` driver). `audio headset status\|test\|chat-only on\|off\|mute\|mirror tv\|never`. |
| `headset/install-xone.sh` | One-time root script: installs [xone](https://github.com/dlundqvist/xone) v0.5.8 with DKMS (Secure Boot: uses the enrolled DKMS key) + the Wireless Adapter firmware. xpad is only loaded when xone isn't built for the running kernel, so a kernel update xone can't build for never leaves a USB controller without a driver. `--uninstall` undoes it. |
| `bin/discord-voice` | Join / leave / mute / deafen a Discord voice channel from the controller, via Discord's local RPC as **your own** Discord application (no user token, no self-bot). `discord-voice setup` once. |
| `bin/wow-music` + `soloist.service` | Spotify in the background for WoW sessions. `battlenet --wow` starts your playlist (shuffled) and switches the game's own music off; when WoW exits the music stops. Uses **Spotify Soloist**, Spotify's official headless player (about 55 MB instead of ~1 GB for the desktop app), and falls back to the desktop app (minimized) when Soloist isn't set up. From the controller, in game too: hold **Share** + right stick right/left = next/previous track, up/down = music volume, tap Share = play/pause. `wow-music playlist <link>`, `wow-music toggle\|next\|prev\|vol up\|down\|N`, `wow-music off`. |
| `bin/discord-overlay` + `autostart/` | Starts [Discover Overlay](https://github.com/trigg/Discover) (Flatpak `io.github.trigg.discover_overlay`) — who's in voice / speaking, over the game; Discord's own overlay doesn't run on Linux. |

Per profile, `couch wow-prep` toggles addons in every character's `AddOns.txt`:

- couch: Easy Controller + CouchWheels
- desk: Bartender4
- always: CouchUI (+ CouchLights from [govee-wow](https://github.com/GrayManSam/govee-wow) if installed),
  and if installed Auctionator, Pawn, Questie + QuestieDB, TomTom, GTFO
- never: ConsolePort (it taints Forever's own gamepad UI: "execution tainted by 'ConsolePort'"),
  QuestieTrace (Questie's optional gameplay recorder)

`Config.wtf` keeps its CRLF line endings when edited.

Combat logs: CouchUI keeps combat logging on (light sync and smart music read it) and WoW
never deletes a log, so `couch wow-prep` prunes `Logs/WoWCombatLog*.txt` before every launch:
the 3 newest stay (as long as they total under 300 MB; the newest always stays).

## Requirements

- Fedora / any distro with GNOME 49 (Mutter `gdctl`), PipeWire (`pactl`), Python 3.11+.
- WoW: Forever via Battle.net under GE-Proton + umu-launcher (paths are variables at the top of
  `bin/battlenet`). Default game folder:
  `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_` — set `WOW_DIR`
  if yours differs.
- Addons from CurseForge/Wago: **Easy Controller** (couch), **Bartender4** (desk). Suggested,
  all with Forever builds: Auctionator (Wago), Pawn, TomTom, GTFO (WoWInterface), Questie
  (GitHub releases). GTFO: open its settings with `/gtfo options`, not from the Options window
  (its panel there gets the gamepad UI's actions blocked while it is open).
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

### Music (optional)

```sh
wow-music playlist https://open.spotify.com/playlist/...   # what plays with WoW
```

That alone works with the Spotify desktop app. For the headless player (Spotify Premium):

1. Download [Spotify Soloist](https://developer.spotify.com/documentation/soloist) and put the
   `soloist` binary in `~/.local/bin/` (builds expire after 90 days; `wow-music update` fetches
   the current one, and does so by itself once a build is 60 days old).
2. Create your own API key at <https://developer.spotify.com/dashboard/soloist> and save it:
   `echo "SOLOIST_API_KEY=..." > ~/.config/wow-music/soloist.env && chmod 600 ~/.config/wow-music/soloist.env`
3. `wow-music pair`, then pick **WoW Couch** in the device list of any Spotify app on the same
   network. Once.

Open-source players (spotifyd, librespot...) no longer work: Spotify refuses them audio keys.

**Smart mode** (default once scanned; headless player only): `wow-music scan` reads the whole
playlist, listens to each song's 30 s preview and sorts the songs into calm / steady / intense
by loudness and punch. While you play it works like a game's own music engine, reading the
combat log (CouchUI turns logging on): a song always plays to its end, and where you are decides
the *next* one — calm exploring or in a city, steady in dungeons and raids, one step livelier
while you fight a lot. Only a boss (at once), PvP or one fight of 45 s+ out in the world cut in
with battle music, and afterwards the interrupted song continues where it stopped. No song comes
back until most of its mood was heard (remembered across sessions, never the same artist twice
in a row); a silent intro is skipped the first time (the player's own stream is measured with
`parec`) and remembered, silent endings are cut. Share + right stick left restarts the song, or
goes back one in its first 8 s. `wow-music moods all` shows the sorting, `wow-music tag
calm|steady|intense` re-sorts the song that is playing, `wow-music mode random` is plain
shuffle. Situations, zones and timings are in `~/.config/wow-music/config.json`.

**Sound quality.** Soloist streams 160 kbps unless told otherwise and has no switch for it;
`wow-music` writes the preference the desktop app uses, so it plays **lossless** (FLAC,
`wow-music quality lossless|very_high|high`). On the TV the music goes through its own sink
with a TV-speaker EQ (`wow-music eq on|off`, bands in the config) straight to the TV: the
game's EasyEffects chain (EQ + compressor) never touches it. Add `Spotify` and `wow-music-eq`
to the blocklist of your EasyEffects game presets; `audio wow start|route` put the music back
on its path after EasyEffects starts. `pipewire/client-10-quality.conf` raises the resampler
quality for the 44.1 -> 48 kHz conversion.

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

## Guild invites

WoW Forever forbids guild invites from addons and macros (`C_GuildInfo.Invite` — "macro script
has been blocked"); only a typed `/ginvite` goes through, and `/ginvite` with no name invites
the target. So the **Recruit** macro only targets, and the PC types the invite: CouchUI flashes
an event on the CouchLights strip, govee-wow sees it in its screen capture and types Enter,
`/ginvite`, Enter, Esc into the game with `xdotool` (needs govee-wow running with the strip).
Each press asks one player; nobody is asked twice (`/couch recruit` = stats, `reset`). Keep the
chat box closed when you press it. `pad` has an older button-based trigger (LT + D-pad right,
`touch ~/.config/padmode/recruit`); it misses presses because Easy Controller keeps the LT layer
on after LT is released, so it is off by default.

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
