# App Store submission checklist — Tinbox

Emulators are allowed under **App Review Guideline 4.7** (retro game console emulators may run games
not embedded in the binary) as long as the app never ships or links to copyrighted games. Tinbox
runs mGBA as an interpreter (no JIT) and only loads files the user imports — the category Apple
approved for Delta, RetroArch, PPSSPP and Provenance. Guideline 2.5.2 (downloading code that
changes the app) does not apply: nothing Tinbox loads alters the app's own features.

## Already done in the project

- [x] Native Swift/ObjC++ binary; no JIT, no code download.
- [x] No bundled ROMs in the app (the CI test ROM lives only in `Tests/`).
- [x] Open-source licences viewable in-app: Settings › About (mGBA MPL-2.0, libpng, zlib/minizip, inih).
- [x] mGBA's MPL obligation: our only modification is `Scripts/mgba-ios.patch`, published in this repo.
- [x] Privacy policy: `PRIVACY.md` (linked from About; use the raw GitHub URL in App Store Connect).
- [x] `ITSAppUsesNonExemptEncryption = NO` (HTTPS only).
- [x] Debug launch arguments compiled out of Release (`#if DEBUG`).
- [x] `NSMotionUsageDescription` for tilt/gyro cartridges.
- [x] App icon (1024 master + full icon set), launch screen, dark-only UI.
- [x] Cloud-sync UI hidden (needs the paid-account entitlement first).

## You need (one-time)

1. **Apple Developer Program** ($99/yr) → App Store Connect access, TestFlight, year-long installs.
2. In Xcode's Signing (or `CODE_SIGN_STYLE=Automatic` + `DEVELOPMENT_TEAM` in `Scripts/gen_xcodeproj.py`),
   set your Team. The bundle ID `com.redfernsoutpost.tinbox` must be registered to it.
3. Build an **archive** on a Mac (or add a signed-archive CI job with an App Store Connect API key and
   a distribution certificate/profile stored as GitHub secrets — ask and I'll add it).
4. In App Store Connect: create the app, fill the listing, upload screenshots, submit.

## Listing: what to write (and what not to)

- **Name**: Tinbox. **Subtitle**: "Game Boy & GBA emulator" is fine.
- **Description**: describe features (themes, save states, rewind, fast-forward, controllers,
  backups). **Do not** mention Nintendo game titles, "ROM downloads", or where to get games.
  Say "play your own backups of games you own".
- **Keywords**: emulator, game boy, gba, retro, handheld.
- **Category**: Games › Utilities (or Entertainment). **Age rating**: 4+.
- **Privacy policy URL**: https://github.com/Keatonmx/tinbox/blob/main/PRIVACY.md
- **Support URL**: the repo's issues page.

## App Privacy questionnaire (App Store Connect)

| Question | Answer |
|---|---|
| Does the app collect data? | **No** for all categories — nothing is collected or linked to identity. |
| Tracking | No |
| Third-party SDKs | None (no analytics/ads SDKs). |

Optional features that use the network but collect nothing: box-art download (GitHub), RetroAchievements
sign-in (credentials go directly to retroachievements.org). Mention these in *Review Notes*.

## Review notes to paste

> Tinbox is a Game Boy / Game Boy Advance emulator (Guideline 4.7). It contains no games and no links
> to games; users import files they own through the system Files picker. Emulation is interpreter-only
> (mGBA, MPL-2.0; licences are shown in Settings › About). Optional network use: downloading cover art
> from the open-source libretro-thumbnails project, and an optional RetroAchievements sign-in. No
> analytics, ads or accounts. To test: a small homebrew test cartridge is attached for review
> (`Tests/tinbox-test.gba` from the repository) — import it via Files › Tinbox › ROMs.

Attach `Tests/tinbox-test.gba` as the demo file so reviewers can run something without a commercial ROM.

## Common rejection traps

- Description or screenshots showing Nintendo titles → reword / use the test cartridge or a homebrew game.
- "Download games" wording anywhere → remove.
- Missing licence texts for MPL code → already in About.
- Crash on first launch with no games → CI's library screenshot covers this case.
