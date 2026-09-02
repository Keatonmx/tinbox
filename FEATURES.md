# Tinbox — Features

A native iOS Game Boy Advance / Game Boy / Game Boy Color emulator by Redfern's Outpost,
built on the mGBA core. No accounts, no ads, no analytics.

## Emulation

- GBA, GB, GBC and SGB ROMs, also zipped; the right core is picked per game automatically
- Accurate audio with dynamic rate control (survives games that switch sample rate mid-play)
- Real-time clock synced to the phone: berries grow, day and night pass
- **Game clock shift** (Settings › Advanced): push the RTC forward +6 h / +1 d / +3 d / +7 d for time-based events
- Cartridge hardware emulation: tilt, gyro, rumble (mapped to iPhone haptics) and the Boktai solar sensor
  - Sun slider with haptic detents per level
  - **Auto sun**: the sun level follows ambient light (via screen brightness with auto-brightness on)
  - A JRPG-style cue appears once if Auto sun reads a pitch-black room
- **Game Boy Camera**: the phone camera feeds the emulated cartridge; permission is requested only when a camera cart asks
- GBA BIOS: built-in (HLE) or your own `gba_bios.bin`
- ROM patching (IPS/UPS/BPS) creates a permanent patched copy; originals are never modified

## Saving & the Time Capsule

- In-game battery saves written automatically; leaving a game fills the Auto slot; an emergency snapshot covers interruptions
- **Low battery protection**: at 10% the MENU pill's power LED turns red (like a real GBA) and a capsule snapshot is captured
- 10 save-state slots (Auto + 9), each with a screenshot; import and export via Files; overwrite or delete per slot
- **Time Capsule**: an automatic timeline of the whole playthrough
  - A snapshot every 2/5/10 minutes of play, plus on exit and on demand (Capture)
  - Day-grouped filmstrip with a large preview; jump to any moment (the current spot is stashed in the Auto slot first)
  - Storage self-manages: old stretches thin out instead of being deleted
  - **Postcards**: share any moment as a framed, pixel-perfect image
- Back up saves & states to a zip (Files, iCloud Drive, AirDrop); restore merges it back; the capsule is included

## Playback

- Fast-forward 0.5× to Max via chips or the Quick Menu toggle
- Optional **» scrubber button**: hold and slide right to fast-forward, left to rewind live; double-tap to lock
- Rewind with 30 / 60 / 120 s history, plus a one-tap Rewind 10 s
- Turbo A / B, output volume, and a mix-with-music mode (game audio over Spotify etc.)
- **Speedrun timer**: on-screen RTA splits, deltas against your per-game personal best

## Display

- Portrait: Pixel-perfect / Fit / Fill · Landscape: Fit / Wide / Fill
- Screen filters: CRT, Grid, xBR upscaling
- 120 Hz UI on ProMotion displays; emulation locked to a clean 60
- Boot flourish: a per-game GBA cartridge (tinted plastic, your cover as the label, real header code) slides in and the tin's lid opens — toggleable, and skipped under Reduce Motion

## Controls

- Multi-touch layer: 8-way d-pad, rolling between buttons, many buttons at once, direction-change haptics
- **Layout editor**: drag and pinch every control; per-game layout profiles
- Bluetooth controllers with **full button remapping** (every element assignable, or off)
- Press glow in White or Accent; landscape button opacity; optional rotate button
- The MENU pill carries the power LED: green running, amber paused, red on low battery

## Library

- Cover art: automatic box-art download (libretro-thumbnails, fuzzy name matching), or set your own from **Photos** or Files
- A shrink-wrap sheen over covers; games without art wear a MissingNo. placeholder in their own colour
- Search, sort (recent / A–Z / size), a Continue card with the latest save, system badges
- **Inside the save**: Gen-3 Pokémon games show trainer, playtime and party, read from the battery save
- Choose any Files/iCloud folder as the ROM library; imports always copy
- **Duplicate detection**: byte-identical imports ask first — add anyway, rename (for patching projects), or skip
- Per-game overrides: screen scaling, filter, turbo, button opacity
- Everything (ROMs, saves, states, covers, timeline) is visible in the Files app

## Identity & extras

- 11 themes — **Tin** (the icon's olive & LED green) is the default, **Glass** renders frosted material panels over a glow from your game's cover; one is hidden
- 7 controller skins (Surplus pairs with Tin)
- Stamped TINBOX® branding; the tin's clamshell boot; a handful of affectionate easter eggs
- RetroAchievements sign-in for progress viewing
- Open-source licences, privacy policy and a feedback link (GitHub issues) in About
- Privacy: everything stays on the phone; the only network use is optional box art and optional RetroAchievements

