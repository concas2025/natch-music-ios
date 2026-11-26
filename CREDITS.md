# Credits & Attribution

**Natch Music (iOS)** is a native Swift / SwiftUI / C++17 / Metal iOS port based on the architecture, database schema, stream-extraction pipeline, audio engine, lyrics system, and design language of **Mochy Music** (Android).

This project is **100% free and open-source software** licensed under the **GNU General Public License v3.0 (GPL-3.0)** — with zero paywalls, zero ads, and zero locked features.

---

## Primary Upstream Project

- **Mochy Music** — https://github.com/realidkroo/Mochy-Music (GPL-3.0)
  - Database schema v47 design, InnerTube client catalog (`VISIONOS` primary + fallbacks), last-byte `Range` cutoff validator, `po_token.html`, `TrackMatcher`, multi-source router, C++17 `stage/` 3D Room engine & `stage_hrtf.bin`, `CrossmixStyles`, `MixIt`, `LyricsHelper` grading, and 10 `PlayerStyle` UI architecture.

## Ancestors & Open-Source Libraries

- **ViviMusic**, **Metrolist**, & **InnerTune** — Upstream Android YouTube Music client foundations.
- **MIT KEMAR Compact HRTF Set** (Bill Gardner & Keith Martin) — Embedded via `stage_hrtf.bin` inside `MochyDSP`.
- **AutoEq** — Headphone frequency response parametric EQ target curves.
- **yt-dlp / EJS Solver (`meriyah.js`, `astring.js`, `yt.solver.core.js`)** — Bundled AST cipher & `n`-parameter solver run via Apple `JavaScriptCore`.
- **BgUtils (`po_token.html`)** — BotGuard Proof-of-Origin Token generation bridge via `WKWebView`.
- **Lyrics Ecosystem:** `BetterLyrics`, `Unison`, `YouLyPlus (LyricsPlus)`, `SimpMusic`, `LRCLib`, `LrcRed`, `NetEase`, `KuGou`.
- **GRDB.swift** — https://github.com/groue/GRDB.swift (MIT) — Swift SQLite toolkit backing the v47 WAL database.
- **Apple Frameworks:** SwiftUI, Metal (`ShaderLibrary`), CoreGraphics, AVFoundation (`AVAudioEngine`, `AVPlayer`), Accelerate, CoreHaptics, MusicKit, ShazamKit, MediaPlayer, Network (Bonjour), JavaScriptCore, WebKit, ActivityKit, CarPlay.
