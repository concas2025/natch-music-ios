# Natch Music (iOS)

A native Swift / SwiftUI / C++17 / Metal music player for iOS 17+, ported from [Mochy Music](https://github.com/realidkroo/Mochy-Music).

Licensed under **GPL-3.0** (see [`LICENSE`](LICENSE) and [`CREDITS.md`](CREDITS.md)). **100% free forever — zero paywalls, zero ads, zero locked features.**

---

## Download & Install (`.ipa`)

1. Open the **[Releases](../../releases)** page of this repository.
2. Download the latest `NatchMusic-vX.Y.Z-unsigned.ipa` (for example `NatchMusic-v1.0.0-unsigned.ipa`).
3. Sideload onto your iPhone/iPad with **AltStore**, **SideStore**, **Sideloadly**, or **TrollStore**.

---

## Publishing Future Updates

Push changes to `main` and create a version tag to automatically run tests, archive, package `.ipa`, and publish a new GitHub Release:

```bash
git add -A
git commit -m "Update v1.0.1"
git tag v1.0.1
git push origin main --tags
```

---

## Architecture & Implemented Modules (Phases 1–7)

See [`MOCHY_IOS_BLUEPRINT.md`](MOCHY_IOS_BLUEPRINT.md) for the full design specification.

| Module | Contents |
| :--- | :--- |
| **`MochyCore`** | Preferences & all 10 `PlayerStyle` enums, Keychain `SecretVault`, `SAPISIDHASH` & JioSaavn DES crypto, `TrackMatcher`, `LookSettingKey` whitelist |
| **`MochyDatabase`** | `GRDB.swift` SQLite WAL v47 (all 25 tables, 19 indices, 3 views, cascades, `song_edit`, `playlist_transition`, `speed_dial_item`, stats/import tables) |
| **`MochyInnerTube`** | `VISIONOS` primary + full client fallback chain, `JavaScriptCore` EJS cipher/`n`-solver, `WKWebView` BotGuard `PoTokenGenerator`, last-byte `Range` validator, Home/Search/Next/Video stream extraction |
| **`MochyModules`** | `SourceModulesRouter` (parallel speculative walk + 12s timeout), `MonochromeModule` (FLAC `STREAMINFO` hi-res probe), `JioSaavnModule` (320k AAC), `WebModule`, `JSScriptModule`, `AppleMusicModule` (MusicKit), `ModuleUrlGuard` |
| **`CMochyDSP` + `MochyDSP`** | Mochy's real C++17 `stage/` 3D Room engine + MIT KEMAR `stage_hrtf.bin`, 10-band EQ + `AutoEq`, Crossmix HPF/LPF/Mid-Side/Echo/Reverb/8D Orbit FX processor, LUFS/Silence detector, Audio Pass blocker guard |
| **`MochyLyrics`** | TTML / Enhanced LRC / KRC parsers, parallel fetcher across 11+ providers (`BetterLyrics`, `Unison`, `YouLyPlus`, `SimpMusic`, `LrcLib`, `LrcRed`, `NetEase`, `KuGou`, `LocalFile`, `YouTubeCaptions`), `pickBest` script/duet grader, `CFStringTransform` romanization, Google/OpenRouter translator, `LyricsAutoSync` |
| **`MochyAudio`** | Dual-deck `AVAudioEngine` + remote `AVPlayer` pipeline, WebM/EBML Opus packet demuxer, 512 KB chunk LRU disk cache, all 19 `CrossmixStyle` AI DJ transitions + tempo analyzer, FFT spectrum & `CoreHaptics` bass pulse, `MPNowPlayingInfoCenter` |
| **`MochySync`** | Two-way YTM sync + undo, Spotify/Apple/Tidal/SoundCloud/YouTube `LinkImporter`, RFC4180 CSV importer/exporter, `TransferArchive` backup, `ShazamKit`, `LastFmScrobbler`, Discord Gateway Presence, Bonjour `_mochy-link._tcp` LAN service, iCloud/WebDAV sync |
| **`MochyUI` + `App`** | ForceDark OLED theme + `ArtworkPaletteExtractor` + Metal `.metal` shaders, floating `NavPill`, morphing `BottomSheetPlayer`, `Home` (3 styles + Speed Dial), `Search`, `Library` (`IndexGlide` + `SongEdit`), `AudioLab`, `MixIt` studio, `ShareStudio`, all **10 `PlayerStyle` UIs**, plus `ActivityKit` & `CarPlay` bridges |
