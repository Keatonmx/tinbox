# Handoff: Tinbox — iOS GBA Emulator

## Overview
A lightweight iOS Game Boy Advance emulator ("Tinbox") for iPhone 15 Pro. Dark, iOS-native design: game library, in-game touch controls (portrait + landscape), quick menu with fast-forward / save states / cheats, Files-based ROM and save-state import, and full settings (video scaling, filters, BIOS mode, controller support).

## About the Design Files
The files in this bundle are **design references created in HTML** — an interactive prototype showing intended look and behavior, not production code. The task is to **recreate these designs natively in SwiftUI/UIKit** (no iOS codebase exists yet; SwiftUI with a UIKit `EmulatorViewController` for the Metal game view is the recommended stack). `GBA Player.dc.html` is the prototype; `ios-frame.jsx` only draws the device bezel/status bar and should be ignored (the real app gets those from iOS).

## Fidelity
**High-fidelity.** Colors, spacing, typography, and interactions are final intent. Recreate pixel-perfectly using native equivalents (SF Pro = system font; sheets = native `.sheet` with custom dark styling; switches = `UISwitch`/`Toggle` tinted to the accent).

## Engine architecture (agreed direction — read first)
- Wrap the open-source **mGBA core (libmgba, C)** — do NOT write an ARM7TDMI/PPU core from scratch. Build libmgba via CMake as an xcframework and link it behind an ObjC++ bridge.
- Use the **real mGBA API** (read the headers; do not trust pasted pseudocode): attach video with `setVideoBuffer` sized via `desiredVideoDimensions`; input via `core->setKeys()` (never poke `REG_KEYINPUT`); one `core->runFrame()` per 60 Hz `CADisplayLink` tick (no cycle math); ROM loading via `mCoreLoadFile`; save states via mGBA's VFile-based state calls; cheats via `mCheatDevice` (supports GameShark / Action Replay / CodeBreaker).
- Render the 240×160 framebuffer with **Metal**, nearest-neighbor sampling for Pixel-perfect mode; CRT/Grid filters are fragment-shader variants.
- Audio: low-latency CoreAudio/AVAudioEngine ring buffer pulling from the core.
- Battery saves: mGBA writes native `.sav` automatically once the sandbox `Documents/Saves` dir is configured.
- ROMs live in `Documents/ROMs`, states in `Documents/States` — both visible in the Files app (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`).
- Bluetooth controllers via the GameController framework; haptics via `UIImpactFeedbackGenerator(style: .light)` on touchDown.
- Interpreter only (no JIT) — full speed for GBA on modern iPhones and App Store-viable.

## Design Tokens
Colors (dark theme only):
- App background: `#0E0E11`; canvas behind screen: `#000`
- Card / list background: `#26262B`; sheet background: `#1B1B1F`; input/well: `#131317`; secondary button: `#39393D`
- Accent (primary): `#8C7BF4`; accent text on dark: `#A99BFF` (landscape variant `#B5A9FF`)
- Accent tint fill: `rgba(140,123,244,0.16)` with `1px solid rgba(140,123,244,0.5)` border
- Destructive: `#FF6961`
- Text: primary `#FFF`; secondary `rgba(235,235,245,0.6)`; tertiary `rgba(235,235,245,0.45)`; quaternary `rgba(235,235,245,0.3)`
- Separators: `rgba(84,84,88,0.5–0.65)` at 0.5px; hairline borders `rgba(255,255,255,0.06–0.14)`
- Physical button gradients: circles `linear-gradient(#45454C, #2C2C31)`; pills/D-pad `linear-gradient(#3A3A40, #26262B)`; all with inset top highlight `rgba(255,255,255,0.1–0.16)`

Typography (SF Pro / system):
- Large title 34/700; sheet title 20/700; row text 16/400; row subtitle 12; card title 15/600; meta 12–13; buttons 14/700; control labels (SELECT/START/MENU) 11/700, letter-spacing 1px
- Monospace (SF Mono) for cheat codes (12px), placeholder labels, file-type badges

Radii: sheets 34 (top corners); cards/lists 18; game covers 14; segmented container 14 / segment 12; pills & buttons fully rounded; inputs 10.
Toggles: iOS-standard 51×31, knob 27, accent track when on.
Min hit target: 44px.

## Screens

### 1. Library
- Header: "GBA PLAYER" eyebrow (12/600, uppercase, tertiary) over "Library" large title; trailing 44px circular settings button (opens Settings sheet).
- 2-column grid (16px gap, 20px side padding) of games: square cover (striped placeholder — replace with ROM box art or auto-generated tile), title 15/600, meta line "8.2 MB · 2h ago".
- Last tile: dashed-border "+ Import ROM" (accent plus) → opens ROM import (see 6).
- Tap a game → In-game.

### 2. In-game (portrait)
- Top bar: back (exits to Library, triggers auto-save if enabled), centered game title 15/600, rotate button (switches to landscape).
- Game screen: full-width 3:2 viewport on black band, 6px corner radius, hairline border. FF badge (accent pill "» 3×") top-right of viewport when fast-forward is on.
- Controls (bottom region, 18px side padding, 46px bottom padding):
  - L / R pills 96×34 at top corners of the control area
  - D-pad 150×150 cross (two overlapping rounded rects, 50px arms, radius 14) left; center recessed dot; directional arrows at 30% white
  - A and B 66px circles right, diagonally offset (A upper-right, B lower-left)
  - Optional FF button: 44px circle "»" above A; accent-filled when active; visibility controlled by "FF button on screen" setting
  - Bottom row: SELECT · MENU · START pills 84×34. MENU is the accent-tinted one and opens the Quick Menu.
- All buttons: press = translateY(1px) + darken, plus light haptic.

### 3. Quick Menu (bottom sheet over game)
- Grabber, "Quick Menu" title, accent "Resume" pill (also closes on backdrop tap).
- Card 1: Fast Forward row (subtitle "3× speed") with 2×/3×/4× segmented control + toggle; "FF button on screen" toggle.
- Card 2 rows: Save State (detail "Auto slot"; saves + toast "State saved · Auto"), Save States ›, Cheats › (detail "2 active"), Settings ›.
- Card 3: "Exit Game" centered, destructive color.

### 4. Save States (bottom sheet)
- Header: back-to-menu chevron, "Save States" title, accent "Import" button (opens save-state import, see 6). Game name below.
- 5 slots (Auto, Slot 1–4): 84×56 thumbnail (state screenshot; dashed "empty" placeholder), name 16/600, timestamp 13 secondary; trailing accent action — "Load" for filled, "Save here" for empty. Both toast and dismiss.

### 5. Cheats (bottom sheet)
- Header: back chevron, "Cheats", accent "+ Add".
- Add form (replaces the button while open): type segmented control (GameShark / Action Replay / CodeBreaker), "Cheat name" text field, monospace code field, Cancel + accent "Add Cheat". Validates both fields non-empty (toast "Enter a name and code").
- List rows: name 16 + small type badge (10/700 in `rgba(255,255,255,0.07)` pill), monospace code below, trailing toggle.

### 6. Import (Files picker, ROM and save-state variants)
- In production this is the native `UIDocumentPickerViewController` limited to content types: ROM = `.gba`/`.zip`, states = `.sav`/`.sst`; picked files are **copied into `Documents/ROMs` / `Documents/States`**.
- The prototype mocks it as a sheet: title, Cancel, "Copies into ‹On My iPhone › Tinbox › ROMs›" accent chip, "RECENTS · FILES" header + filter note ("Showing .gba and .zip"), file rows (38×46 file icon with extension badge, name, size, accent "Import"; unsupported types at 35% opacity, "Unsupported"), and a bottom accent "Browse in Files…" button = the real document-picker handoff.
- After ROM import: game appears at top of library + toast. After state import: fills first empty slot + toast.

### 7. Settings (bottom sheet, scrollable, sections)
- **Playback**: Fast-forward speed (2×/3×/4× segmented); Show FF button in game (toggle).
- **Video**: Display scaling (Pixel-perfect / Fit / Stretch); Screen filter (None / CRT / Grid); Boot (HLE / BIOS file — subtitle "HLE needs no BIOS file"; BIOS file choice should prompt a Files import of `gba_bios.bin`).
- **Controls**: Edit button layout › (opens a drag-and-resize overlay editor — not yet designed, build a simple edit mode over the in-game screen); Bluetooth controller › (detail "None connected"; GameController pairing).
- **General**: Haptics on buttons (toggle); Battery saves (info row, "Native .sav files, backed up automatically"); Auto-save on exit (toggle, subtitle "Writes a state to the Auto slot"); About row.

### 8. In-game (landscape)
- Fullscreen game (Fit/Stretch per setting), device rotated.
- Overlay controls at **65% opacity (user-adjustable 30–100%)**: L/R top corners, D-pad 140px lower-left, A/B 62px lower-right, FF button right edge, SELECT/MENU/START 80×30 pills bottom center. FF badge top center.
- MENU opens a compact centered dialog (420px, radius 26): title + Resume, then 4 tiles 64px: FF toggle (accent when on), Save, More… (returns to portrait full menu — in the real app just present the full sheet), Exit (destructive).

## Interactions & Behavior
- Sheets slide from bottom, dim backdrop `rgba(0,0,0,0.55)`, backdrop tap dismisses.
- Toasts: centered pill near bottom, `rgba(44,44,48,0.95)`, 14/600 white, ~1.8s, fade/slide in 250ms. Used for: state saved/loaded, imports, cheat added, auto-save on exit, validation.
- Toggle knob animates 180ms.
- Fast-forward state, speed, and all settings persist (UserDefaults); per-game: cheats, save states, last-played.
- Exit game: if Auto-save on exit is on, write state to Auto slot + toast.

## State Management
- App: `games[]` (name, size, lastPlayed, coverArt), `settings` (ffSpeed, showFFButton, scaling, filter, biosMode, haptics, autosaveOnExit, controlOpacity).
- Session: `currentGame`, `isFastForward`, `orientation`, `activeSheet`.
- Per game: `saveSlots[5]` (screenshot, timestamp), `cheats[]` (name, code, type, enabled).

## Assets
No image assets — all UI is vector/native. Striped placeholders in the prototype mark where ROM box art / state screenshots render.

## Files
- `GBA Player.dc.html` — the full interactive prototype (all 8 screens; open in a browser)
- `ios-frame.jsx` — bezel/status-bar chrome for the prototype only; do not implement


## Branding & Theming (update)
- Product name: **Tinbox**, by **Redfern's Outpost** (byline appears only in Settings › About: "Tinbox 1.0 · Redfern's Outpost").
- Two user-switchable themes (Settings › Appearance › Theme; persist in UserDefaults). **Modern is the default** — it is the violet theme all tokens above describe.
- **Outpost theme** (modern-rustic earth tones) overrides: accent #C97B4A (copper), accent text #E0A277 / #E8B08A, accent tint rgba(201,123,74,0.16) with rgba(201,123,74,0.5) borders, FF badge rgba(178,104,58,0.92); backgrounds: app #14100B, sheet #1E1812, card #282017, input well #17120D, chip #211A13, secondary button / off-track #3E342A. Grey physical-button gradients, text colors, separators, and destructive red are shared between themes.
- Implement colors as a semantic token set (accent, accentText, tint, tintBorder, bg, sheet, card, well, chip, secondaryButton) resolved from the active theme — see the THEMES object in the prototype's logic for the exact mapping.
- App icon concept: `Tinbox Icon.dc.html` — dark warm squircle, copper tin box with stamped d-pad cross + two button dots.

## Feature set v2 (all free — no Pro tier, no ads)
UI is designed in the prototype for: speed slider 0.25×–100× with preset chips (below 1× = slow motion) in Quick Menu + Settings; Rewind (30 s ring buffer; "Rewind 10 s" action in Quick Menu; toggle in Settings); Turbo A/B rapid-fire toggles (Quick Menu; accent dot on the button when armed); Auto-suspend save (emergency state on resign-active/phone call); Background audio mixing (user's music over game SFX); Controller skins screen (built-ins: Modern graphite, Outpost Wood walnut, Grape Classic purple — skin recolors D-pad/A/B/pill gradients; marketplace row = spec-only, "Coming soon"); Cloud saves (Off / iCloud / Google Drive segmented + "Sync now" row; iCloud via CloudKit/ubiquity container, Drive via Google Sign-In SDK); RetroAchievements sheet (user chip with points, Hardcore mode toggle that disables states+cheats, per-game achievement list with earned/locked states via rcheevos library); Apply ROM patch row (IPS/UPS on-the-fly via document picker, original file untouched); Sensor cartridges info row (mGBA supports tilt/solar/rumble — map to CoreMotion, brightness slider overlay, and haptics); Layout profiles row (per-game saved button layouts; editor is the drag-resize overlay from phase 9).
Spec-only (no UI yet): skin marketplace backend, per-game profile management screen.
Explicitly excluded: link-cable multiplayer, ads/telemetry, paywalls.

## Quick Menu IA (v3 reorganization)
Quick Menu order: (1) action tile row — Save (auto slot) / Load / Rewind 10 s (accent-tinted); (2) Speed card — FF toggle, 0.25×–100× slider, preset chips; (3) navigation card — Save States ›, Cheats ›, Settings ›; (4) Exit Game. Turbo A/B toggles and the "Show FF button" toggle live in Settings › Controls and Settings › Playback respectively — the Quick Menu holds only mid-game actions.