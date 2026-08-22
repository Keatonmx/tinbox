# Claude Code kickoff prompt (paste into Claude Code from the project root containing design_handoff_gba_player/)

Build a native iOS Game Boy Advance emulator app called "Tinbox", implementing the design spec in `design_handoff_gba_player/README.md` exactly. Read that file first — it contains all screens, design tokens, interactions, and the agreed engine architecture. The bundled HTML file is a design reference prototype, not code to port.

## Stack
- Xcode project, iOS 16+, iPhone (portrait + landscape). Swift + SwiftUI for all UI; one UIKit `UIViewController` hosting an `MTKView` for the emulator display.
- Emulation core: **mGBA (libmgba, C)** — clone https://github.com/mgba-emu/mgba, build as a static lib/xcframework via CMake for ios-arm64 (+ simulator), link behind an Objective-C++ bridge. Do NOT write a CPU/PPU core from scratch. No JIT — interpreter only.

## Engine integration (use the real mGBA headers, not memory)
- Bridge class `GBAEmulatorCore` (ObjC++): init core via `mCoreFind("gba")` + config init; size and attach a BGRA buffer with `desiredVideoDimensions` + `setVideoBuffer`; load ROMs with `mCoreLoadFile`; input via `core->setKeys(core, mask)` using mGBA's GBA key enum; run exactly one `core->runFrame()` per tick; save/load states via mGBA's VFile state API with screenshot flag; cheats via `mCheatDevice` (GameShark / Action Replay / CodeBreaker); set core dirs so battery `.sav` files land in `Documents/Saves` automatically.
- Loop: `CADisplayLink` at 60 Hz drives runFrame → copy framebuffer to an `MTLTexture` → draw fullscreen quad. Nearest-neighbor sampler for "Pixel-perfect"; "CRT" (scanlines) and "Grid" as fragment-shader variants; "Fit"/"Stretch" change quad geometry. Fast-forward = run 2/3/4 frames per tick (audio muted or resampled).
- Audio: AVAudioEngine source node pulling from the core's audio buffer (32768 Hz), ring buffer, low latency.
- BIOS: default HLE; "BIOS file" setting imports `gba_bios.bin` via document picker and calls the core's BIOS load.
- Files: `Documents/ROMs` and `Documents/States`; Info.plist `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`. Import via `UIDocumentPickerViewController` filtered to .gba/.zip (ROMs) and .sav/.sst (states); copy picks into those folders.
- Controllers: GameController framework, standard mapping for Xbox/PS/MFi; hide touch overlay when a controller connects.
- Haptics: `UIImpactFeedbackGenerator(style: .light)` on touchDown of every control (respect the Haptics setting).

## UI (recreate pixel-perfectly from the README — tokens and layouts are all there)
Screens: Library (2-col grid + Import ROM tile), In-game portrait (D-pad, A/B, L/R, SELECT/MENU/START, optional FF button), Quick Menu sheet (FF toggle + 2×/3×/4×, save/load, cheats, settings, exit), Save States sheet (5 slots with screenshots, Import button), Cheats sheet (type badges + add form with type picker), Import sheets (native document picker), Settings sheet (Playback / Video / Controls / General sections), In-game landscape (fullscreen + translucent overlay controls at adjustable opacity, compact quick menu dialog).
Dark theme only. Accent #8C7BF4. System font. Toasts for save/load/import confirmations. Persist settings in UserDefaults; per-game state (slots, cheats, last-played) on disk.

## Order of work
1. Xcode project scaffold + mGBA xcframework build script (document the CMake invocation).
2. GBAEmulatorCore bridge + Metal renderer + display link; boot a homebrew test ROM.
3. Touch controls + input mapping + haptics.
4. Audio.
5. Library + ROM import + persistence.
6. Save states + battery saves + auto-save on exit.
7. Quick menu, fast-forward, cheats.
8. Settings (scaling, filters, BIOS, controllers) + landscape mode.
9. "Edit button layout" drag-and-resize overlay editor (simple: drag to move, pinch to scale, saved per orientation).

Verify each phase compiles and runs in the simulator before moving on (core runs in sim as interpreter). Only ship code that works against the actual mGBA headers you cloned.


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