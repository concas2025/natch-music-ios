# Mochy Music — Kiến Trúc Toàn Diện & Bản Thiết Kế Port Sang iOS (~90–95% Parity) cho Neon

> **Tài liệu nguồn chuẩn (Single Source of Truth)** được phân tích trực tiếp từ mã nguồn gốc [`realidkroo/Mochy-Music`](https://github.com/realidkroo/Mochy-Music) (`versionName = "8.5.0.0 build#1308"`, `versionCode = 73`, `MusicDatabaseVersion = 47`, `MODULE_API_VERSION = 3`).
> **Mục đích:** Giúp **Neon** (và các model AI kế tiếp) đọc một lần là nắm 100% cấu trúc Android hiện tại của Mochy Music và triển khai bản **native iOS (Swift 6 / SwiftUI / Metal / AVAudioEngine / C++17 DSP / GRDB)** đạt độ tương đồng 90–95% về cả UX/UI lẫn năng lực xử lý âm thanh, stream và lyrics.

---

## 0. Quy Tắc Bắt Buộc Từ Repo Gốc (`AGENTS.md` & GPL-3.0)

Mọi code Neon tạo ra cho bản iOS **PHẢI** tuân thủ 3 quy tắc cứng từ `AGENTS.md` của Mochy Music:

1. **Giữ nguyên Credit & Bản quyền (GPL-3.0):**
   - Mochy Music là phần mềm mã nguồn mở GPL-3.0 của `realidkroo` (`https://github.com/realidkroo/mochy-music`), được fork từ **ViviMusic** (`vivizzz007`), xây trên nền **Metrolist** (`Mostafa Alagamy`), cùng các thư viện/API nguồn mở: `InnertubeX` (`MetrolistGroup`), `SimpMusic`, `LRCLib`, `BetterLyrics`, `LyricsPlus` (`YouLyPlus`), `Unison`, `lrc.red`, `Monochrome Music`, `ArchiveTune`, `RiMusic / InnerTube`, `AutoEq`.
   - Khi port sang iOS (dù giữ tên hay đổi tên), **BẮT BUỘC** ghi rõ credit về Mochy Music và các dự án nền ở tối thiểu: `README.md`, file `NOTICE`/`CREDITS`, comment đầu `App` entry point, và màn hình **About / Giới thiệu** trong app.
2. **Không Paywall / Không Quảng Cáo (No Paywalls):**
   - Tuyệt đối **không** thêm subscription, gói Pro/Premium, khóa tính năng sau đăng nhập trả phí, key bản quyền hay Ad SDK. Mọi tính năng phải miễn phí cho tất cả người dùng (nếu có mục ủng hộ/Donate thì phải là tùy chọn và không mở khóa bất kỳ tính năng nào).
3. **Không Hardcode Secret / API Key:**
   - Không commit các key như Last.fm API key/secret, Discord Client ID, Dropbox/OneDrive Client ID, OpenRouter/DeepL/Mistral key vào source code. Lưu token người dùng trong **iOS Keychain**.

---

## 1. Tổng Quan Cấu Trúc Repo Android & Kiến Trúc Đích Trên iOS

### 1.1. Cấu trúc đa module của `realidkroo/Mochy-Music` (22 Gradle subprojects + 3 Native C++ libs)

| Nhóm Module | Danh sách module trong `settings.gradle.kts` | Vai trò cốt lõi |
| :--- | :--- | :--- |
| **App Core** | `:app` (`com.mochyy.mochymusic`, minSdk 24, targetSdk 37) | Jetpack Compose UI, Hilt DI, Room DB v47, `MusicService` (Media3 ExoPlayer), Audio Lab, Crossmix/MixIt, Lyrics orchestrator, Importers/Sync, Mochy Link LAN, Cast (`gms`/`foss`), Android Auto (`car`), Widgets, Floating Pill |
| **Plugin/Module API** | `:modules:api`, `:modules:bridge` | Interface chuẩn `MochyModule` (`MODULE_API_VERSION = 3`), `TrackMatcher`, `Wire` IPC cho module rời |
| **Built-in Stream Modules** | `:modules:monochrome`, `:modules:applemusic`, `:modules:jiosaavn` | Nguồn phát nhạc tích hợp sẵn (FLAC lossless Monochrome, Apple Music web playback, JioSaavn 320k AAC) |
| **Providers (16 modules)** | `:providers:innertube`, `:providers:betterlyrics`, `:providers:paxsenixlyrics`, `:providers:youlyplus`, `:providers:lrclib`, `:providers:simpmusic`, `:providers:kugou`, `:providers:directlyrics` (Deezer, NetEase, QQMusic, LrcRed, Unison), `:providers:musixmatch`, `:providers:genius`, `:providers:canvas`, `:providers:applecanvas`, `:providers:artistvideo`, `:providers:shazamkit`, `:providers:lastfm`, `:providers:wikipedia` | Các client API thuần Kotlin gọi dịch vụ tìm kiếm nhạc, lấy stream YouTube, 14+ nguồn lyrics, canvas video động, nhận diện nhạc, scrobbling và tiểu sử bài hát/nghệ sĩ |
| **Native C/C++17 (`app/src/main/cpp`)** | `libmochyfx.so` (+ `jamesdsp_eel2`), `libmochystage.so`, `libmochypass.so` (+ `libusb`) | DSP Mixer/FX + VM biên dịch script `.eel` LiveProg; Phòng âm thanh 3D HRTF (`stage_hrtf.bin`); USB DAC driver & AAudio exclusive passthrough |

### 1.2. Cấu trúc Xcode Workspace & Local Swift Packages đề xuất cho iOS (`MochyiOS`)

Neon nên tổ chức repo iOS theo kiến trúc modular sạch (tương ứng 1-1 với Android):

```text
mochy-ios/
├── MochyApp.xcodeproj / Package.swift
├── App/                            # App lifecycle, RootShellView, CarPlay SceneDelegate, URL schemes
├── Extensions/
│   ├── MochyWidgets/               # WidgetKit (Home Screen & Lock Screen widgets)
│   └── MochyLiveActivity/          # ActivityKit (Dynamic Island & Lock Screen Live Lyrics/Progress)
└── Packages/
    ├── MochyCore/                  # AppPreferences (@AppStorage/UserDefaults), Keychain SecretVault, Proxy/DoH HTTP client
    ├── MochyDatabase/              # GRDB.swift SQLite WAL (25 tables + 3 views khớp schema v47)
    ├── MochyInnerTube/             # InnerTube API, YouTubeClient catalog, YTPlayerResolver, JSContext solver, WKWebView PoToken
    ├── MochyModules/               # MochyModule Swift protocols, SourceModules router, Monochrome/JioSaavn/WebModule, ModuleSkin JSON
    ├── MochyLyrics/                # 14+ lyrics providers, TTML/LRC/KRC/RichSync parsers, pickBest grader, CFStringTransform romanizer, AI translate, Audio AutoSync
    ├── MochyDSP/                   # Copy trực tiếp C/C++17 `fx/`, `stage/`, `jamesdsp_eel2/`, `stage_hrtf.bin` + extern "C" wrapper (bỏ JNI & libusb)
    ├── MochyAudio/                 # Dual-deck AVAudioEngine, 512KB Range Cache, CrossmixDirector/Planner, MixItEngine, AutoEq, CoreHaptics, MPNowPlayingInfoCenter
    └── MochyUI/                    # SwiftUI Views, Metal (.metal) Shaders, 10 PlayerStyles, PlayerStudio, Share Studio (AVAssetWriter MP4), Recap Story
```

---

## 2. Tầng Lấy Link Nhạc & Giải Mã Stream (Stream Resolution Pipeline — Chi Tiết 100%)

Đây là trái tim giúp Mochy phát nhạc ổn định từ nhiều nguồn (YouTube, Monochrome FLAC, JioSaavn, Apple Music, WebModule, file local) mà không bị lỗi đứng hình ở giây thứ ~30.

### 2.1. Luồng phân giải Just-In-Time (`DynamicResolvingMediaSource` -> `MusicService`)

1. **Nguyên tắc bất di bất dịch:** Hàng đợi phát (`Queue`) **KHÔNG bao giờ** lưu link CDN trực tiếp (vì link `googlevideo.com` hết hạn sau vài giờ). Mỗi bài trong queue chỉ lưu `mediaId` + `MediaMetadata`.
2. **Generation Guard:** Khi deck chuẩn bị phát bài (`prepareSourceInternal`), tăng biến đếm `generation`. Mọi tác vụ mạng bất đồng bộ nếu hoàn thành khi `generation` đã đổi (do user bấm Next liên tục hoặc đổi chất lượng) đều bị hủy/bỏ qua.
3. **Thứ tự ưu tiên giải quyết nguồn (`fetcherAction` trong `MusicService.kt`):**
   - **Bước 1 — `deviceStream(mediaItem)` (Local & Offline Bypass):**
     - Nếu URI là `file://`, `content://`, hoặc `mediaId` bắt đầu bằng `"LOCAL_"` -> đọc file cục bộ, gắn nhãn `"This device"`.
     - Nếu `isFullyDownloaded(mediaId)` -> phát từ `DownloadCache`, gắn nhãn `"Your downloads"`.
     - Nếu có trong `PhoneFiles` (Mochy Link LAN) -> stream qua HTTP nội bộ `"Your phone"`.
     - Nếu `OfflineMode.isOn == true` và không có trong cache đầy đủ -> ném `OfflineModeException`, tự động chuyển sang `nextOfflineIndex()`.
   - **Bước 2 — `forcedRoutes[mediaId]` (`ProviderSwitch`):**
     - Khi người dùng bấm **"Force change"** trong bảng `StreamInfoSheet`, `ProviderSwitch` tạm dừng phát, thử gọi `host.resolve(providerId, mediaId)` tối đa `MaxTries = 20` lần trong `DeadlineMs = 60_000 ms` (delay tăng dần `(attempt * 400).coerceAtMost(3000)` ms), sau đó reload đúng vị trí `currentPosition` từ provider được ép.
   - **Bước 3 — `SourceModules.route(...)` (Parallel Speculative Walk):**
     - Thứ tự mặc định (`KnownOrder`): `["monochrome", "applemusic", <các module cài thêm như "jiosaavn">, "youtube"]`. (Hàng đợi tải xuống `downloadOrder` tách riêng và chỉ nhận `StreamFormat.Progressive && drm == null`).
     - Nếu provider đứng đầu có thể dùng là `"youtube"` -> bỏ qua bước gọi module, đi thẳng sang YouTube.
     - Nếu có các module đứng trước `"youtube"` -> **gọi song song (parallel `async`) tất cả module đứng trước YouTube cùng một lúc** với tổng ngân sách thời gian `ModuleTimeoutMs = 12_000 ms`! Sau đó duyệt câu trả lời **đúng theo thứ tự ưu tiên**. Hễ module đầu tiên đạt chuẩn (`ModuleUrlGuard.sanitizeStream` + `DeviceDecoders.canPlay`), lập tức `.cancel()` các task còn lại.
     - Nếu module fail hoặc phone không có decoder cho sampleRate/codec đó -> ghi vào `failedSources` (nhớ trong `FailedSourceMemoryMs = 10 phút`) và `forceFallBack()` chuyển sang provider kế tiếp ngay tại timestamp hiện tại!

### 2.2. Chi tiết kỹ thuật các Built-in Source Modules

1. **`MonochromeModule` (Lossless FLAC / Hi-Res FLAC, không cần tài khoản):**
   - Server mặc định: `https://tracks.monochrome.st` (`Kind.Streamer`). Hỗ trợ thêm `ServerListModule` cho phép user dán URL web Monochrome bất kỳ -> tự động nhận diện API trực tiếp hoặc quét tối đa 4 thẻ `<script src>` (`MaxScripts = 4`) tìm domain `tracks.*` / `*relay*`.
   - Search:
     - `Streamer`: `GET {base}/search/tracks?q={artist coreTitle}&limit=8` (đọc mảng `tracks[]`).
     - `Relay`: `GET {base}/search?q={query}&n=8` kèm header `X-Relay-Client: relay/2` (đọc mảng `data[]`, tách nghệ sĩ bằng `(?<! )&(?! )`).
   - Chọn bài bằng `TrackMatcher.ranked(track, candidates)` (so khớp ISRC, tiêu đề sau khi bóc tag `(feat...)`/`[Remastered]`, nghệ sĩ, độ dài `durationMs`).
   - Kiểm tra stream bằng `Range: bytes=0-41`:
     - `Streamer`: `GET {base}/track/{id}`
     - `Relay`: `GET {base}/s/{id}?q=flac`, lấy URL thật từ response header `X-Relay-Stream` (chỉ nhận URL cùng origin).
   - Parse header **FLAC `STREAMINFO`** tại bytes `0..25`: kiểm tra magic `"fLaC"`, đọc 20-bit `sampleRate` và 5-bit `bitsPerSample` -> hiển thị `"FLAC"` hoặc `"Hi-Res FLAC · 24-bit / 96 kHz"`. Nếu thiết bị không hỗ trợ sample rate này -> chuyển provider kế tiếp.
   - Cache miss `30 phút` (`MissMemoryMs`), đánh dấu server chết `10 phút` (`UnreachableRetryMs`).

2. **`JioSaavnModule` (AAC 320/160/96 kbps, không cần tài khoản, không DRM):**
   - Search: `GET https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=android&p=1&n=10&q={query}` với header `Cookie: explicit_content=1`.
   - Giải mã link nhạc: Base64-decode trường `more_info.encrypted_media_url` -> giải mã **DES/ECB/PKCS5Padding** với khóa cố định 8 byte: **`MediaKey = "38346591"`**.
   - Nâng cấp bitrate: Regex `_(12|48|96|160|320)\.(mp4|m4a|aac|mp3)(?=[?#]|$)` thay bằng `_320` nếu user chọn AAC 320, rồi kiểm tra bằng `Range: bytes=0-1`.

3. **`WebModule` (REST Module chuẩn JSON từ link GitHub / URL / file `.zip`):**
   - Tải `{base}/manifest.json`.
   - `GET {base}/search?q={query}&quality={LOSSLESS|HI_RES_LOSSLESS|HIGH|LOW}&atmos={...}` -> nhận danh sách `tracks[]` (có thể trả `streamURL` trực tiếp hoặc gọi tiếp `GET {base}/stream/{id}`).
   - Hỗ trợ tự nhận diện `Progressive` / `Hls` / `Dash`, codec (`FLAC`, `ALAC`, `AAC`, `Opus`, `DOLBY ATMOS` / `eac3-joc`), `sampleRate`, `bitDepth`, và tự fallback từ `HiRes` xuống `Lossless` nếu thiết bị không decode được 192kHz.

4. **`AppleMusicModule` (Sự khác biệt bắt buộc giữa Android & iOS):**
   - *Trên Android:* Mở `WKWebView`/`WebView` tới `music.apple.com`, bắt header `Authorization` (Bearer JWT developer token) và `Media-User-Token` -> gọi `amp-api.music.apple.com` tìm bài -> `POST https://play.itunes.apple.com/WebObjects/MZPlay.woa/wa/webPlayback` lấy `ctrp256` HLS + giải mã qua Android **Widevine CDM** (`acquireWebPlaybackLicense`).
   - *Trên iOS:* iOS **không có Widevine CDM** (Apple dùng FairPlay nội bộ cho AVPlayer). Để giữ tính năng Apple Music trên iOS ở mức ~90%: dùng **`MusicKit` framework chính chủ Apple** (`MusicAuthorization`, `MusicCatalogSearchRequest`, `ApplicationMusicPlayer.shared`). **Lưu ý cho Neon:** Audio phát qua `ApplicationMusicPlayer` đi qua hệ thống bảo vệ DRM của iOS nên sẽ **không đi qua custom DSP `AVAudioEngine`** (nhấn mạnh rõ trong UI Options giống cách Mochy giải thích giới hạn FairPlay), còn `Monochrome` FLAC, `JioSaavn`, `WebModule` và `YouTube` đều đi full qua `AVAudioEngine` + C++ DSP.

### 2.3. Tầng YouTube Music (`InnerTubeX` + `YTPlayerUtils` Client Walk + Anti-Bot)

Mochy dùng 2 tầng song song cho YouTube: mặc định thử `InnerTubeX` (`GiveUpMs = 12_000 ms`, yêu cầu `allowHls = false, allowSabr = false, allowBoundedRange = false` — chỉ lấy direct stream URL), nếu fail hoặc cần 256kbps Premium thì chạy **`YTPlayerUtils` Client Walk**:

1. **Danh sách Client & Thứ tự ưu tiên (`YouTubeClient.kt` & `YTPlayerUtils.kt`):**
   - **`MAIN_CLIENT = VISIONOS` (Quan trọng nhất!):**
     - `clientName = "VISIONOS"`, `clientVersion = "1.04"`, `clientId = "101"`
     - `User-Agent = "com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)"`
     - `osName = "visionOS"`, `osVersion = "26.6.0.23O770"`, `deviceMake = "Apple"`, `deviceModel = "RealityDevice17,1"`
     - `apiOrigin = "https://www.youtube.com"`, `apiFormatVersion = "2"`, `clientScreen = "WATCH"`, `platform = "MOBILE"`, `ownVisitorId = true` (tự mint `visitorData` qua API `visitor_id`).
     - **Lý do `VISIONOS` đứng số 1:** Trả về trực tiếp link audio không bị mã hóa `signatureCipher` (`itag 139/140/249/250/251`), có đầy đủ `audioConfig.loudnessDb` và `playbackTracking`, **không cần `PoToken`**, và tải được trọn vẹn 100% file!
     - **Xử lý Bot Check cho `VISIONOS`:** Nếu `playabilityStatus == "LOGIN_REQUIRED"` và `reason` chứa `"bot"`, app gọi `refreshVisitorData(VISIONOS)` 1 lần và hỏi lại. Nếu vẫn dính bot check lần 2 -> cho `VISIONOS` nghỉ `BOT_CHECK_REST_MS = 30 phút`, chuyển thẳng sang fallback clients.
   - **Nếu user đã đăng nhập YouTube Music Premium** (`wantsPremiumAudio` & `HIGH`/`AUTO` Wi-Fi): ưu tiên dãy client có xác thực để lấy stream **256 kbps** (`PREMIUM_AUDIO_ITAGS = {141, 774, 327, 328, 380, 256, 258}`, ngưỡng `>= 220_000` bps):
     `WEB_REMIX` -> `TVHTML5_SAMSUNG` (5.20260707) -> `WEB_EMBEDDED_PLAYER` -> `TVHTML5_DOWNGRADED` -> `TVHTML5` -> `ANDROID_CREATOR` -> `VISIONOS`.
   - **Dãy Fallback đầy đủ (`STREAM_FALLBACK_CLIENTS`):**
     `VISIONOS` -> `WEB_REMIX` -> `WEB` -> `WEB_CREATOR` -> `IPADOS` -> `ANDROID_VR_1_43_32` -> `ANDROID_VR_1_61_48` -> `ANDROID_VR_1_65_10` -> `ANDROID_VR_NO_AUTH` -> `TVHTML5_SIMPLY_EMBEDDED_PLAYER` -> `TVHTML5` -> `ANDROID_CREATOR` -> `MOBILE`.
   - Nếu là nhạc bị giới hạn độ tuổi (`AGE_CHECK_REQUIRED`, `AGE_VERIFICATION_REQUIRED`, `LOGIN_REQUIRED`, `CONTENT_CHECK_REQUIRED`) khi đã login -> thử `WEB_CREATOR` và các `ACCOUNT_CLIENTS`.

2. **Giải mã `signatureCipher` & biến `n=` (`EjsNTransformSolver` + `CipherDeobfuscator`):**
   - Tải và cache `player.js` (`base.js`) từ YouTube theo hash phiên bản.
   - Mochy đóng gói sẵn bộ giải AST JS từ `yt-dlp-ejs`: `assets/solver/meriyah.js`, `astring.js`, `yt.solver.core.js`.
   - **Lợi thế vượt trội trên iOS:** Thay vì tạo WebView nặng nề như Android, Neon chạy thẳng 3 file JS này + `player.js` trong **`JavaScriptCore` (`JSContext`)** native của iOS! Thời gian giải mã < 5ms, không tốn RAM renderer process.
   - Dùng cho các client có `useWebPoTokens = true` hoặc thuộc `ACCOUNT_CLIENTS` (`solvesN()`): giải mã `s` -> `sig`/`signature` (khi URL nằm trong `signatureCipher`) và biến đổi tham số `n=...` trong URL để `googlevideo.com` không bóp băng thông hoặc trả 403.

3. **Sinh `PoToken` (Proof of Origin Token) bằng `WKWebView` chạy ngầm khi cần:**
   - Chỉ kích hoạt lười (lazy) khi rớt xuống client cần `useWebPoTokens` (`WEB_REMIX`, `TVHTML5`).
   - Load `po_token.html` (BotGuard VM) trong `WKWebView` ẩn: mint `playerRequestPoToken` (theo `dataSyncId` nếu đã login hoặc `visitorData`) để gửi kèm payload `/youtubei/v1/player`, và `streamingDataPoToken` (theo `videoId`) để nối `&pot=...` vào cuối link stream.
   - Đóng `WKWebView` sau `60s` rảnh (`IDLE_CLOSE_MS`); nếu fail liên tiếp -> cooldown `5 phút` (`MINT_COOLDOWN_MS`).

4. **Kiểm tra byte cuối chống lỗi cắt ngang 30 giây (`validateStatus` — BẮT BUỘC):**
   - Các client `IOS`/`IPADOS`/`ANDROID_VR` khi thiếu PoToken vẫn trả mã HTTP 206 ở byte 0 và phát bình thường ~786 KB (~30 giây), rồi **chết cứng HTTP 403** ở giây 31!
   - Trước khi chấp nhận bất kỳ link stream nào, gửi `GET` với header **`Range: bytes={contentLength - 1}-{contentLength - 1}`** (hoặc `bytes=1048576-1048576` nếu không có `contentLength`), kèm **đúng `User-Agent`, `Origin`, `Referer`, `Cookie`** theo client (`WEB_REMIX` dùng `Origin: https://music.youtube.com`, client khác dùng `https://www.youtube.com`). Không dùng `HEAD` vì `googlevideo.com` trả 403 với `HEAD`. Chỉ nhận khi trả `200`/`206` (hoặc `416` nếu `contentLength == null`).

5. **Tối ưu chọn chất lượng, Stand-in, Studio Swap & Chunk Cache:**
   - `selectAudioFormatCandidates`: Lọc audio gốc (`isOriginal`, bỏ track auto-dubbed). Theo `AudioQuality`: `LOW <= 70kbps`, `MEDIUM <= 135kbps` (lọt vào 128k AAC thay vì 160k Opus), `HIGH = null` (lấy cao nhất). Ưu tiên `AUDIO_QUALITY_*` -> Premium -> Channels -> Bitrate -> Codec (`opus > mp4a > other`) -> Direct URL -> SampleRate.
   - `orStandIn`: Nếu toàn bộ client bị YouTube từ chối bản upload này (và không phải lỗi 429/bot check/nhạc riêng tư), tìm tối đa `MAX_STAND_INS = 2` bản upload khác của cùng bài qua `SongVersions.otherUploads`, giữ nguyên metadata bài gốc.
   - `studioVersionOf` (`StudioForVideosKey`): Nếu bài là Music Video, tự tìm bản Audio Studio (`MUSIC_VIDEO_TYPE_ATV`) thay thế để không bị dính tạp âm/intro của MV.
   - **Đọc & Cache theo Chunk `512 KB` (`CHUNK_LENGTH = 512 * 1024`):** Cache URL trong RAM theo `expiresInSeconds`; mỗi lần đọc từ `googlevideo.com` chỉ mở `Range` từng đoạn 512 KB ghi vào disk cache LRU (tránh treo stream & giảm tiêu hao băng thông). Khi bật `SkipBlend`, tự động tải trước `512 KB` đầu của 1–4 bài kế tiếp/trước đó sau `PrefetchDelayMs = 4000 ms`.

---

## 3. Audio Engine, Native C++ DSP ("Audio Lab"), Crossmix & MixIt

### 3.1. Giải pháp Codec trên iOS (Tránh bẫy Opus/WebM!)
- CoreAudio iOS giải mã sẵn phần cứng/phần mềm cho **FLAC (16/24-bit 192kHz), ALAC, AAC-LC / HE-AAC (`mp4a` itag 140/141), MP3, WAV, và Opus (`kAudioFormatOpus`)**.
- **Bẫy lớn nhất:** `AVAssetReader` / `ExtAudioFile` của Apple **không hỗ trợ container WebM/Matroska** (`audio/webm; codecs="opus"`, `itag 251` của YouTube)!
- **Cách xử lý chuẩn 100% cho Neon:**
  1. Viết một **WebM/EBML Matroska Audio Packet Demuxer** gọn nhẹ (~300 dòng C/Swift đọc `Cluster -> SimpleBlock` lấy frame Opus thô + `AVAudioConverter` từ `kAudioFormatOpus` sang `Float32 PCM`). Khi đó `itag 251` (160k Opus) và `itag 774` (256k Opus Premium) phát mượt như Android và giữ nguyên toàn bộ chuỗi DSP!
  2. (Dự phòng): Nếu chưa kịp xong WebM demuxer ở Phase 1, ưu tiên xếp hạng `mp4a` (`itag 141`/`140`) trước `webm` khi chọn format YouTube, trong khi `Monochrome` FLAC chạy trực tiếp qua `AVAudioFile` / FLAC decoder native.

### 3.2. Kiến trúc Dual-Deck `AVAudioEngine` thay thế 2 `ExoPlayer`
Trên Android, `MusicService` phải tạo và swap 2 instance `ExoPlayer` (`player` và `secondaryPlayer`/`fadingPlayer`) cho Crossfade, Crossmix và Blend Skips (`SkipBlend`).
Trên iOS, Neon làm gọn và chính xác sample hơn hẳn bằng **1 `AVAudioEngine` duy nhất** gắn **2 Node Deck song song (`DeckA`, `DeckB`)**:
- Mỗi Deck là một `AVAudioSourceNode` (hoặc `AVAudioPlayerNode` cấp PCM Float32 liên tục từ ring buffer giải mã) nối qua chuỗi xử lý riêng của Deck:
  `Deck PCM Source` -> `AVAudioUnitTimePitch` (điều chỉnh Tempo Match / Speed / Pitch không bị khựng) -> **`CrossmixDeckDSP` (`FxParams`)** -> `MixerMatrix` (gộp Deck A + Deck B).
- **Master Bus sau Mixer (Audio Lab):**
  1. `CustomEqualizer` (Biquad cascade 10–31 band / Parametric EQ từ `AutoEqRepository` + `AutoEqFitter` + EQ riêng từng bài `SongTuning`).
  2. **`MochyFX` (C/C++17 Port trực tiếp `app/src/main/cpp/fx/`):**
     - `mochyfx` + `jamesdsp_eel2` (`MOCHY_EEL_SANDBOX`) viết 100% bằng C11/C++17 chuẩn, **không phụ thuộc Android NDK API** (trừ `fx_jni.cpp` và `__android_log_print`).
     - Neon chỉ việc copy nguyên thư mục `cpp/fx/` và `cpp/third_party/jamesdsp_eel2/` vào Swift Package `MochyDSP`, thay `fx_jni.cpp` bằng cầu nối `extern "C"` gọi từ C++ audio render callback! Giữ nguyên 100%: multi-bus routing, Tone, Dynamics (Compressor/Limiter), Colour, Progenitor Reverb, Loudness LUFS meter, và trình chạy script `.eel` **LiveProg**!
  3. **`MochyStage` 3D Room (`app/src/main/cpp/stage/` + `assets/stage_hrtf.bin`):**
     - Copy nguyên thư mục `cpp/stage/` và file nhị phân `stage_hrtf.bin` (237 KB) vào `MochyDSP`. Giữ nguyên 100% mô phỏng phòng 3D (6 bức tường phản xạ `Walls = 6`, tối đa 4 bản sao mỗi dải `Vocal/Center/Left/Right/Ambience/Sub`, chế độ Tai nghe HRTF / Loa ngoài).
  4. **Các hiệu ứng phụ & Phân tích:** `8D Audio` (auto-orbit panning + Reverb), `ReplayGain` + YouTube `loudnessDb` Normalization + `PeakLimiter`, `SilenceDetector` (nhảy qua khoảng lặng), `AudioSpectrum` (FFT đưa về UI Visualizer), và **`HapticAudioProcessor` -> `CoreHaptics` (`CHHapticEngine`)** rung theo bass kick!

### 3.3. Crossmix (AI DJ Tự Động) & MixIt Studio
- **Crossmix (`crossmix/`):**
  - Bộ phân tích offline/nền (`CrossmixAnalysis`) đo **BPM, Beat Grid, Downbeat/Bar, đường cong năng lượng RMS, điểm Intro/Outro**, cache xuống disk theo `mediaId`.
  - `CrossmixPlanner` chọn 1 trong **19 phong cách chuyển bài (`CrossmixStyle`)**:
    - Dùng hằng ngày (`Everyday`): `SilkBlend`, `BassSwap` (hoán đổi dải bass < 200Hz theo phách), `FilterSweep`, `EchoOut`.
    - Khi năng lượng tăng (`Lift`): `HighPassLift`, `Backspin`, `LoopRoll`, `RiserBuild`.
    - Khi năng lượng giảm (`Fall`): `TapeStop`, `PowerDown`, `Downlifter`.
    - Đậm chất DJ (`Flavour`): `DubThrow`, `ReverbWash`, `RewindWash`, `StutterGate`, `PhaserGlide`, `LofiMelt`, `SpatialOrbit`, `DopplerPass`.
  - `FxParams` điều khiển trực tiếp DSP mỗi deck: `lowCutHz`/`highCutHz`/`resonance`, 3-band EQ, `vocalCenterCut` & `sideCut` (tách mid/side giữ vocal/nhạc cụ khi mix), `bassCut`, `echo` đồng bộ theo nhịp (`echoBeats`, `echoPingPong`), `reverbFreeze`, `gateDepth`/`gateDivision`, `flangerMix`, `crush`, `orbit`, `noiseLevel` riser, và `Deck` stunts (`Loop`, `SpinBack`, `TapeStop`).
- **MixIt (`mixit/` & `ui/mixit/`):**
  - Trình biên tập transition riêng cho từng cặp bài (`fromSongId -> toSongId`) trong Playlist (`MixItEditorSheet` + `MixItWaveformDeck`): hiển thị 2 waveform song song, snap theo beat, vẽ đường fade, bật/tắt `bassSwap`, chỉnh 3 thanh stem `Voice / Bass / Instrument` cho cả bài ra và bài vào, nghe thử trực tiếp trên preview player và lưu xuống bảng `playlist_transition`.

### 3.4. Audio Pass (Bit-Accurate / Bypass DSP)
- *Trên Android:* Dùng `libmochypass.so` (`usbdevfs`/`libusb` + `AAudio` exclusive) cùng danh sách `PassBlockers` (nếu bật EQ/Stage/Mixer/Crossmix/Volume != 100% thì báo blocker và cho bấm 1 nút tắt hết để giữ lại trạng thái cũ vào `AudioPassRestoreKey`).
- *Trên iOS:* Apple **không cho mở raw `/dev/bus/usb`**, nhưng **CoreAudio tự động bit-perfect/hi-res qua USB-C / Lightning DAC** nếu không chèn DSP làm biến đổi sample. Neon dùng `AVAudioSession.sharedInstance().setPreferredSampleRate(Double(trackSampleRate))` + chế độ **"Audio Pass"** tắt/bypass toàn bộ DSP chain (vẫn giữ nguyên cơ chế `PassBlockers` và `AudioPassRestoreKey` lưu snapshot phục hồi 1 chạm!).

---

## 4. Kiến Trúc UI/UX, Motion Choreography, Shaders & 10 Player Styles (~95% Giống Bản Gốc)

### 4.1. Hệ thống Theme, Màu sắc & Typography (`ui/theme/`)
- **Dark-Only (`ForceDarkTheme = true`)** + tùy chọn **Pure Black OLED (`#000000`)**. Toàn bộ text/glass tối ưu trên nền tối.
- **Dynamic Artwork Color Engine (`PlayerColorExtractor`, `ArtworkPalette`):** Resize cover về `100x100`, trích xuất palette bằng thuật toán Quantize/Score (chọn màu nền chủ đạo + 6 màu blob Apple Music + màu accent độ tương phản cao).
- **Fonts & Scale:** Nhúng sẵn `Inter` (Thin đến ExtraBold) và `BBH Bartle` (`res/font/`), hỗ trợ import font `.ttf`/`.otf` người dùng chọn qua `CTFontManagerRegisterFontsForURL`, cùng `DensityScale` (`1.0`, `0.85`, `0.75`, `0.65`, `0.55`) và độ bo góc ảnh bìa toàn app `thumbnailCornerRadius` (`0..45 pt`).

### 4.2. Shell Điều Hướng & Chuyển Động Cốt Lõi (`MainActivity.kt` -> `RootShellView`)
- **4 Tab Chính (`Screens.kt`):** `Home` (`home`), `Search` (`search_input`), `Library` (`library`), `Settings/Profile` (`settings`).
- **Floating Bottom Bar (`NavPill` / `WideBar` + `AppNavigationBar`):**
  - Thanh pill kính mờ nổi ở đáy màn hình, có gradient scrim chuyển màu theo `LocalDetailAccentColor`.
  - Nhấn đúp tab `Search` -> mở ngay bàn phím tìm kiếm.
  - Khi mở Player (`progress` từ `0.0 -> 1.0`), thanh NavBar trượt xuống (`translationY = navBarHeight * progress`) và mờ dần (`alpha = 1 - progress / 0.6`).
- **Morphing `BottomSheetPlayer`:**
  - Kéo từ MiniPlayer lên Fullscreen Player với chuyển động liên tục theo tay (`PlayerSwipeUpFollowsKey`).
  - **Hiệu ứng chiều sâu đặc trưng của Mochy:** Khi sheet player mở, toàn bộ nội dung app phía sau thu nhỏ nhẹ (`scale = 1.0 - 0.06 * progress`) và mờ dần (`alpha = (1 - progress) / 0.25`) bên trong một offscreen compositing layer (`.drawingGroup()` trên SwiftUI) để **không re-render view nền mỗi frame 120Hz**. Khi `progress > 0.82` (`StatusBarLeavesAt`), ẩn thanh Status Bar (`prefersStatusBarHidden = true`) để player tràn viền tuyệt đối (có tùy chọn bật lại).
- **Cover-Recede Navigation (`NavigationBuilder.kt`):**
  - Khi mở Album, Playlist, hoặc Module Store từ Home/Library, màn hình nguồn lùi lại (`scale = 0.92`, `alpha = 0.45`) trên đường cong spring khớp với ảnh bìa đang phóng to ra (trên iOS dùng `matchedGeometryEffect` hoặc iOS 18 `.navigationTransition(.zoom)`).
- **Tối ưu 120Hz ProMotion & GPU:**
  - Ép `120Hz` cho vùng player/lyrics/turntable (`CAFrameRateRange`), nhưng **hãm tốc nền Apple Music Blob ở ~30Hz** (`BlobWakeMillis = 32ms`) và đóng băng mọi animation nền (`LocalAppContentObscured`) ngay khi player che kín màn hình!

### 4.3. Port AGSL / GLES Shaders sang SwiftUI Metal (`.metal`)
Mochy dùng `RuntimeShader` (AGSL API 33+) + fallback GLES 3.0 Dual-Kawase. Trên iOS, Neon viết bằng **Metal Shading Language (`ShaderLibrary`)**:
1. **`AmbientBackdrop` / `AppleMusicBackground`:** 6 vòng tròn radial gradient quỹ đạo sin/cos + warp shader hòa trộn màu bìa album mượt mà.
2. **`FrostedGlass` & `ProgressiveBlur`:** Kính mờ 2 mức (`LOW` nhẹ không nhiễu hạt; `HIGH` blur bán kính động `10..50px` + film grain nhẹ + progressive top/bottom blur mask trên thanh bar và mép bìa nhạc `SeamBlur`).
3. **`LyricsGlowLine`:** Hiệu ứng sáng chữ karaoke mượt, nở/phát sáng từ giữ nốt dài (`LyricsHighBloomKey`) và hòa trộn ánh sáng nhẹ cho các dòng chưa hát (`LyricsSoftLightKey` -> `BlendMode.softLight`).

### 4.4. Toàn Bộ 10 Phong Cách Player (`PlayerStyle`) & `PlayerStudio`
Neon cần dựng đủ 10 preset trong `PlayerStyle` (`PreferenceKeys.kt`):

| # | Tên Preset (`PlayerStyle`) | Mô tả kiến trúc & Yêu cầu UI trên iOS |
| :- | :--- | :--- |
| 1 | **`FLAGSHIP`** (Mặc định) | Bìa Edge-to-Edge mờ mép dưới (`SeamBlur`) hoặc Squared/Disc, 5 kiểu nền (`COVER_GRADIENT`, `SOLID`, `DARK_GRADIENT`, `APPLE_MUSIC`, `AMBIENT`), 3 kiểu nút transport (`THREE`, `TEN_SECONDS`, `QUEUE_REPEAT`), thanh đáy `VOLUME` hoặc `STACK` thẻ Lyrics/Queue xếp chồng, thanh seekbar (`DEFAULT`, `WAVY`, `SLIM`). Hỗ trợ **Player Studio** (giữ lâu để mở chế độ chỉnh trực tiếp: kéo lên/xuống vị trí cụm nút điều khiển `PlayerControlsShiftKey`, kéo dãn chiều cao card `PlayerCardGrowthKey`, đổi slot nút menu chevron, đổi nội dung dòng Title/Subtitle). |
| 2 | **`TURNTABLE`** | Đĩa than vinyl quay theo tốc độ phát (`DiscCover`, nhãn đĩa tùy biến tên/album/nghệ sĩ) kèm cần đọc **Tonearm** (`TurntableArm`): **kéo/xoay kim đĩa than bằng tay để tua nhạc** (`TurntableControls`) + quay ngang sang layout landscape 2 cột. |
| 3 | **`VIDEO`** | Phát YouTube Music Video (`YTPlayerUtils.resolveVideoStreams` từ 144p đến 2160p/4K) toàn màn hình, tự đồng bộ lệch thời gian giữa bản thu Studio và Video (`VideoAudioSync`), kèm bảng Lyrics lơ lửng bên cạnh khi xoay ngang. |
| 4 | **`IPOD`** | Giả lập **iPod Classic** hoàn chỉnh: 4 màu vỏ (`SILVER`, `BLACK`, `U2`, `TRUE_DARK`), tùy chọn màn hình cao (`IpodTallScreenKey`), **Click Wheel xoay góc tròn cảm ứng** (`IpodClickWheel`) có **rung Taptic (`UIImpactFeedbackGenerator`) mỗi nấc xoay**, duyệt toàn bộ thư viện & **Cover Flow 3D** (`IpodCoverFlow`) ngay bên trong màn hình iPod! |
| 5 | **`POSTER`** | Bố cục tạp chí full-bleed kèm tùy chọn vòng **Visualizer phổ tần số** quanh bìa (`PosterVisualizerKey`) chạy theo dữ liệu FFT từ `AudioSpectrum`. |
| 6 | **`TIMELINE`** | Giao diện tối giản tập trung vào thanh tiến trình & typography lớn. |
| 7 | **`LYRICS`** (Lyrics Stage) | Sân khấu lời bài hát toàn màn hình, ưu tiên không gian đọc/karaoke. |
| 8 | **`BEDSIDE`** (Big Clock) | Đồng hồ đặt đầu giường cực lớn ban đêm (`BIG`, `STACKED`, `ANALOG`, `COVER`), tint cam ấm hoặc màu cover (`BedsideNightTint`), khóa màn hình không tắt (`isIdleTimerDisabled = true`), tự dịch nhẹ vài pixel định kỳ chống lưu ảnh OLED (`BedsideScreenSaver`). *(Lưu ý iOS: thay chế độ "hiển thị đè Lock Screen Android" bằng **StandBy Mode widget** hoặc hướng dẫn Guided Access).* |
| 9 | **`BEDSIDE_TILES`** | Phiên bản nằm ngang chia 2 tile cuộn độc lập (1 bên nhạc, 1 bên đồng hồ/lyrics). |
| 10 | **`MODULE`** | Giao diện do `ModuleSkin` JSON quy định (tự render các block, background shader, nút bấm từ JSON). |

### 4.5. Các Màn Hình & Tính Năng UI Quan Trọng Khác
- **Animated Cover Canvas (`CanvasOrder`):** Dùng `AVPlayer` + `AVPlayerLooper` phát lặp video mute (4K HLS hoặc MP4) nằm ngay vị trí artwork, truy vấn theo thứ tự người dùng chọn: **Apple Music Motion Artwork** (`AppleMusicCanvasProvider` tự cào JWT token từ bundle JS của `music.apple.com`), **Tidal / Monochrome Canvas**, **Spotify Canvas**, **Artist Video**.
- **Home (`HomeScreen`):** 3 phong cách (`MOCHYY`, `LISTEN_NOW`, `HOP_IN`), lưới ghim nhanh **Speed Dial** (`SpeedDialHero`), đề xuất cá nhân hóa (`HomeRecommender`), thẻ Recap tháng/năm.
- **Search (`SearchScreen`):** Chuyển đổi `Online` (YouTube) / `Local`, gợi ý tìm kiếm theo vùng từ YouTube + Apple Music (`AppleMusicScraper`), duyệt Mood & Genres.
- **Library (`LibraryHomeScreen`):** Hợp nhất tab Thư viện, Local (quét file Audio + thư mục), Cached/Downloaded, Thể loại từ ID3 tag, Imported từ từng dịch vụ, thanh trượt chữ cái nhanh `IndexGlide`, thao tác vuốt bài hát trái/phải tùy chỉnh (`SongSwipeBox`).
- **Song & Lyrics Share Studio (`ui/player/share/`):** Cho phép chọn từng dòng/từ lyrics, chọn nền blur/gradient/video, xuất ảnh thẻ hoặc **xuất video MP4 karaoke có nhạc + hiệu ứng động** (trên iOS dựng bằng **`AVAssetWriter` + `AVVideoCompositionCoreAnimationTool`** ghép frame với audio gốc).
- **Stats & Monthly/Yearly Recap (`StatsScreen`, `RecapStory`, `ProfileIdCard`):** Thống kê nghe nhạc, story Recap có nhạc nền snippet, và thẻ ID người dùng lật 3D (`USR#` + ngày tham gia).

---

## 5. Hệ Sinh Thái Module & Skin (`MochyModule` API v3 & `ModuleSkin`)

Trên Android, Mochy hỗ trợ 4 nguồn nạp module: Built-in, APK rời (`PathClassLoader`), Code Zip, và **Web/File JSON/Zip Module** (`WebModule` / `LocalModule`).
**Trên iOS (cấm tải mã thực thi động DEX/dylib từ ngoài):**
- **Giữ 100% các module built-in** (`Monochrome`, `JioSaavn`, `AppleMusic` qua MusicKit) + **100% hệ thống `WebModule` (URL/JSON) và `LocalModule` (`.zip` chứa `manifest.json`, hình ảnh, font, Metal/GLSL fragment hoặc shader presets, custom pages, theme `LookSetting`)** + có thể mở rộng thêm **JS Scripting Modules chạy trong `JSContext`** (cho phép cộng đồng viết module nguồn nhạc/lyrics bằng JavaScript an toàn 100% đúng quy định Apple)!
- **Mọi lớp bảo mật giữ nguyên (`ModuleUrlGuard`, `ModuleSanitizer`, `SecretGuard`):** Chặn module tự ý truy cập `localhost`/LAN IP private, chặn gửi cookie hệ thống, giới hạn dung lượng đọc `manifest.json` (`MaxManifestBytes = 256 KB`), và lưu storage riêng từng module mã hóa trong Keychain/Encrypted file.
- **Whitelist `LookSetting`:** Module giao diện chỉ được đổi các key an toàn (`playerStyle`, `homeStyle`, `playlistStyle`, `thumbnailCornerRadius`, `lyricsMotionStyle`, `blur`, `blurQuality`, `blurStrengthPx`, `enableProgressiveBlur`, `elementBlur`, `pureBlack`, `accentColor`, `dynamicTheme`, `playerBackground`, `flagshipBackground`, `ipodTheme`, `ipodWheelColor`, `bottomBar`), không bao giờ được đụng vào tài khoản, network hay playback.

---

## 6. Hệ Sinh Thái Lyrics (14+ Nguồn, Thuật Toán Chấm Điểm, Auto-Sync & Dịch AI)

### 6.1. Danh sách 14+ Nguồn & Thứ tự ưu tiên (`LyricsProviderRegistry`)
- **Ưu tiên 0 (Offline):** Embedded lyrics trong tag file nhạc (`ID3 USLT/SYLT`, FLAC/Vorbis `LYRICS`, MP4 `©lyr`) và file `.lrc`/`.ttml` cùng tên nằm cạnh file nhạc.
- **Thứ tự online mặc định:**
  `[Active Lyrics Modules]` -> `BetterLyrics` (Apple Music TTML word-timed & duet) -> `Unison` -> `YouLyPlus` (LyricsPlus) -> `Paxsenix` -> `LrcRed` -> `SimpMusic` -> `LrcLib` -> `Deezer` -> `YouTubeSubtitle` -> `YouTubeMusic` -> `NetEase` -> `QQMusic` -> `KuGou` -> `YouTubeCaptions` *(chỉ hỏi sau cùng nếu tất cả nguồn trên đều rỗng)*.

### 6.2. Thuật toán chọn lời chuẩn ngôn ngữ gốc (`LyricsHelper.pickBest`)
Mochy không lấy bừa nguồn đầu tiên trả về (vốn hay làm bài tiếng Anh/Nhật bị dính bản dịch tiếng Trung từ KuGou/NetEase). Mọi nguồn thường được gọi **song song** (`ProviderTimeoutMs = 35_000 ms`) rồi chấm điểm theo công thức chính xác:

1. **Xác định `referenceScript` của bài hát:**
   - Lấy script chi phối từ Title + Artist + Album (`HAN`, `KANA`, `HANGUL`, `DEVANAGARI`, `CYRILLIC`, `ARABIC`, `LATIN`, `UNKNOWN`), hoặc nếu metadata viết bằng Latin thì hỏi `YouTubeMusic` / `YouTubeSubtitle` (nguồn gắn với chính video ID đó).
   - **Quy tắc Nhật-Trung:** Nếu `referenceScript == HAN` nhưng có ít nhất 1 candidate chứa `KANA` -> bài là tiếng **Nhật (`KANA`)**, tránh để lời Trung Quốc thắng.
   - **Tầng lọc (`eligible`):** Các dịch vụ Trung Quốc (`KuGou`, `NetEase`, `QQMusic`) bị tách riêng: chỉ được xét ngang hàng khi là bài tiếng Hoa (`chineseSong`), hoặc khi chúng có **word-timed lyrics đúng ngôn ngữ bài hát**.
2. **Công thức chấm điểm:**
   $$\text{Score} = \text{scriptScore} \times 1{,}000{,}000 + \text{timedScore} \times 100{,}000 + \text{hindiBonus}(10{,}000) + \text{featureScore} \times 1{,}000 + \text{orderScore}$$
   Trong đó:
   - `scriptScore`: khớp hoàn toàn = `3`, cùng họ CJK = `2`, không xác định = `1`, sai ngôn ngữ = `0`.
   - `timedScore`: có timestamp (line/word) = `1`, plain text = `0`.
   - `featureScore = (hasDuet ? 4 : 0) + (wordTimed && !syllableSplit ? 3 : 0) + (hasBackgroundVocals ? 2 : 0)`.
   - Nếu user bật `LyricsOrderOverrideKey`, `orderScore` được xét ngay sau `timedScore`.

### 6.3. Render nâng cao, Phiên âm, Dịch AI & Tự căn nhịp (`LyricsAutoSync`)
- **Format hỗ trợ:** TTML (`ttm:agent` song ca trái/phải, giọng bè `x-bg`, timing từng từ/âm tiết), Enhanced LRC (`<mm:ss.xx>`), KRC, LRC thường, cộng chấm nhịp nghỉ `LyricsInterludeDots`.
- **Phiên âm (Romanization) không tốn dung lượng trên iOS:** Thay vì đóng gói `kuromoji-ipadic` (20MB) + `tinypinyin`, iOS dùng thẳng API hệ thống **`CFStringTokenizer` + `CFStringTransform`** (`kCFStringTransformToLatin`) cho Nhật (Romaji), Trung (Pinyin), Hàn (Romanized Hangul), Nga/Kirin, Hindi/Devanagari!
- **Dịch lời bài hát:** Hỗ trợ phụ đề dịch sẵn của YouTube (`YouTubeCaptionTranslation`), Google Translate, DeepL API, và dịch stream bằng LLM qua **OpenRouter** / **Mistral**.
- **Tự động căn lệch giây (`LyricsAutoSync`):** Đọc file âm thanh trực tiếp đang phát (hoặc luồng YouTube đối chiếu nếu stream hiện tại là HLS/DASH DRM), phân tích hoạt độ giọng hát (`VocalActivity`) để tìm `lyricsOffset` (ms) chuẩn xác và lưu vào `SongEntity`.

---

## 7. Database Schema (v47), Sync 2 Chiều, Importer & Hệ Sinh Thái Tích Hợp

### 7.1. SQLite Schema (`MusicDatabase.kt` — `mochy.db` -> `GRDB.swift` WAL)
Giữ nguyên toàn bộ **25 Bảng & 3 SQL Views** (mode WAL, `busy_timeout = 60000`):
- **Core Catalog & Library:** `song` (`SongEntity`), `artist` (`ArtistEntity`), `album` (`AlbumEntity`), `playlist` (`PlaylistEntity`), `song_artist_map`, `song_album_map`, `album_artist_map`, `playlist_song_map`.
- **Playback & Metadata:** `format` (`FormatEntity` — lưu `itag`, `mimeType`, `codecs`, `bitrate`, `sampleRate`, `contentLength`, `loudnessDb`, `perceptualLoudnessDb`), `lyrics` (`LyricsEntity`), `related_song_map`, `set_video_id` (lưu `setVideoId` YouTube để sửa/xóa playlist từ xa), `song_edit` (**Bảng tách riêng** lưu sửa tay của user về tên/nghệ sĩ/bìa/custom `videoId` để sync online không bao giờ ghi đè mất!).
- **History, Stats & DJ:** `event` (`Event`), `play_count` (`PlayCountEntity`), `playlist_event` (`PlaylistEvent`), `search_history`, `recognition_history`, `speed_dial_item` (lưu pin trang chủ), `playlist_transition` (`PlaylistTransition` — lưu toàn bộ cấu hình **MixIt** của từng cặp bài trong playlist).
- **Import Tracking:** `imported_song`, `import_session`, `import_session_song`, `imported_playlist`, `imported_playlist_track` (lưu thông tin nguồn Spotify/Apple/Tidal/CSV để Re-sync và tránh đẩy nhầm lên YouTube khi bật `YtExcludeImportsKey`).
- **3 Views:** `sorted_song_artist_map`, `sorted_song_album_map`, `playlist_song_map_preview`.

### 7.2. Đồng bộ YouTube Music, Import Đa Nền Tảng & Tích Hợp Ngoài
1. **YouTube Music 2-Way Sync (`YouTubeSyncManager` + `SyncUtils`):**
   - Đăng nhập bằng `WKWebView` tại `accounts.google.com` -> bắt cookie (`SAPISID`), `visitorData`, `dataSyncId`, tên/email/handle -> lưu an toàn trong iOS Keychain.
   - Sinh header xác thực `Authorization: SAPISIDHASH {ts}_{sha1(ts + " " + sapisid + " https://music.youtube.com")}`.
   - Đồng bộ Liked Songs, Library, Playlists, Lịch sử nghe (`YouTubePlayReporter` gửi `videostatsPlaybackUrl`/`watchtimeUrl` chỉ khi dùng authenticated client), hỗ trợ **Hoàn tác Sync (`SyncUndo`)** và **Tùy chọn cô lập nhạc import (`YtExcludeImportsKey`)**.
2. **Import Từ Spotify / Apple Music / Tidal / SoundCloud / CSV:**
   - `AccountImportSession`: Mở `WKWebView` trang chính chủ (`open.spotify.com`, `music.apple.com`, `listen.tidal.com`), bắt session token từ request header/cookies để kéo thư viện & playlist (không lưu mật khẩu).
   - `LinkImporter`: Phân tích link công khai Spotify / Apple Music / Tidal / SoundCloud / YouTube playlist.
   - `CsvImport` & `MochyCsvExporter`: Nhập CSV tùy chỉnh cột (tương thích TuneMyMusic / Exportify). Match bài bằng `TrackMatcher` + hỗ trợ `PlaylistResync` đồng bộ lại.
3. **Cloud Backup & Local Transfer:**
   - Đóng gói `.zip` (`TransferArchive`: DB + playlist + settings + ảnh đại diện + edits).
   - Đồng bộ đám mây tự động qua **iCloud Drive** (`FileManager.url(forUbiquityContainerIdentifier:)` — ưu tiên iOS), **Dropbox** (PKCE OAuth), **OneDrive** (PKCE OAuth), **WebDAV** lên lịch chạy nền qua `BGProcessingTaskRequest`.
4. **Tích hợp ngoài:**
   - **Nhận diện nhạc (`ShazamKit`):** iOS có **`ShazamKit` (`SHManagedSession`)** chính chủ Apple -> nhận diện bài hát từ micro chỉ với vài chục dòng Swift, lưu vào `recognition_history`!
   - **Discord Rich Presence (`DiscordGateway`):** OAuth2 PKCE + WebSocket `wss://gateway.discord.gg` phát trạng thái đang nghe, đếm thời gian, 2 nút bấm tùy chỉnh, và **upload GIF bìa đĩa xoay / Canvas video (`CanvasGif` / `SpinningArtwork`)** qua `PictureHosts`.
   - **Scrobbling:** **Last.fm** (ký MD5 `api_sig`) & **Libre.fm** với `ScrobbleTimer` và hàng đợi offline `ScrobbleQueue`.
   - **Mochy Link (Điều khiển & Stream qua Wi-Fi LAN):** Thay `NsdManager`/HTTP server Android bằng **Bonjour (`NWListener` + `NWBrowser`)** để ghép đôi iPhone với Mochy Desktop / Android TV / Apple TV dùng chung giao thức HTTP/WebSocket JSON của `LinkControlRoutes` & `PhoneLibraryRoutes`.

---

## 8. Bảng Đối Chiếu Android -> iOS (Cách Clone ~90–95% Giống Nhất)

| Thành phần trên Android (Mochy) | Không mang sang iOS được vì | Giải pháp trên iOS để đạt 90–95% Parity | Mức độ giống |
| :--- | :--- | :--- | :---: |
| **Media3 `ExoPlayer` (Dual instance)** | Thư viện Java/Android riêng | **`AVAudioEngine` Dual-Deck** (`DeckA`/`DeckB`) + HTTP Range Cache + WebM/Opus demuxer -> `AVAudioConverter` | **95–100%** |
| **Native C++ `mochyfx` (`jamesdsp_eel2`) & `mochystage`** | JNI (`fx_jni.cpp`, `stage_jni.cpp`) | **Copy nguyên 100% C/C++17** + `stage_hrtf.bin`, thay mỗi file JNI bằng `extern "C"` bridge vào CoreAudio render callback | **100%** |
| **USB Direct `libusb`/`usbdevfs` & `AAudio` (`AudioPass`)** | iOS không cho user-space mở USB raw fd | `AVAudioSession.setPreferredSampleRate(trackRate)` + tự bypass chuỗi DSP (`PassBlockers`) cho DAC USB-C/Lightning | **85–90%** |
| **AGSL `RuntimeShader` & GLES 3.0 Fallback** | API đồ họa Android (`API 33+`) | **SwiftUI Metal Shaders (`.metal`)** — chạy mượt 120Hz trên 100% iPhone hỗ trợ iOS 16/17+ | **95–100%** |
| **Floating Lyrics Pill (`SYSTEM_ALERT_WINDOW`)** | iOS cấm app vẽ cửa sổ đè lên app khác | **2 giải pháp kết hợp:** (1) **Dynamic Island & Live Activities (`ActivityKit`)** hiện lời bài hát trực tiếp ngoài Home/Lock Screen; (2) **Picture-in-Picture (`AVPictureInPictureController`)** render khung lời cuộn thực sự nổi đè lên mọi app khác! | **90%** |
| **Apple Music Module (Web + Widevine CDM)** | iOS không có Widevine CDM cho AVPlayer | Dùng **`MusicKit` (`ApplicationMusicPlayer`)** chính chủ (lưu ý không đi qua C++ DSP) + giữ `Monochrome` FLAC cho người muốn Audio Lab | **85%** |
| **Cipher / `n`-solver WebView (`EjsNTransformSolver`)** | Android `WebView` + `JavascriptInterface` | **`JavaScriptCore` (`JSContext`)** native — chạy `meriyah.js`, `astring.js`, `yt.solver.core.js` không cần UI/WebView, nhanh gấp 10x | **100%** |
| **BotGuard `PoTokenWebView`** | Android `WebView` | **`WKWebView` ẩn** nạp `po_token.html`, tự hủy sau 60s idle | **95–100%** |
| **Nạp Module `.apk` rời (`PathClassLoader`)** | iOS cấm tải code thực thi động từ ngoài | Giữ Built-in + **`WebModule` JSON** + **`ModuleSkin` Zip** + mở rộng **JS Plugin trong `JSContext`** (an toàn 100% sandbox) | **85–90%** |
| **Google Cast (`GMS`) & DLNA** | Play Services Cast SDK là riêng cho Android | **AirPlay 2 (`AVRoutePickerView`)** tích hợp hệ thống + **Google Cast iOS SDK** (hoặc UPnP/DLNA SSDP trên LAN nếu muốn FOSS 100%) | **90%** |
| **Android Auto (`CarAppService`)** | Framework xe hơi Android | **CarPlay Audio App (`CPTemplateApplicationSceneDelegate`, `CPListTemplate`, `CPNowPlayingTemplate`)** | **90%** |
| **Bedside hiển thị đè Lock Screen** | `setShowWhenLocked` là cờ Activity Android | Fullscreen OLED burn-in safe + `isIdleTimerDisabled = true` + **StandBy Mode** WidgetKit (khi cắm sạc xoay ngang trên iOS 17+) | **85%** |
| **Shazam Signature Generator tự viết** | Tự tính FFT fingerprint | **`ShazamKit` (`SHManagedSession`)** có sẵn của Apple | **100%** |
| **Kuromoji + TinyPinyin (20MB+)** | Thư viện Java NLP nặng | **`CFStringTokenizer` & `CFStringTransform`** dựng sẵn trong Foundation/CoreFoundation (0 MB dung lượng thêm) | **95%** |
| **Home Screen Widgets & Quick Shortcuts** | RemoteViews XML | **WidgetKit** (Small/Medium/Large + Interactive Play/Pause/Like/Lyric tracker intents) | **95%** |

---

## 9. Lộ Trình 7 Phase Để Neon Triển Khai Project iOS

1. **Phase 1 — Core, Database & Stream Extraction Engine (`MochyCore`, `MochyDatabase`, `MochyInnerTube`):**
   - Dựng Xcode Workspace + Swift Packages. Implement `GRDB.swift` với đủ 25 bảng + 3 views v47.
   - Implement `InnerTube` client, `VISIONOS` + chuỗi fallback client, `JSContext` solver (`meriyah.js`/`astring.js`/`yt.solver.core.js`), `WKWebView` `PoTokenGenerator`, và **bắt buộc viết unit test kiểm tra `Range` byte cuối (`validateStatus`)**.
2. **Phase 2 — Multi-Source Router & Dual-Deck `AVAudioEngine` (`MochyModules`, `MochyAudio`):**
   - Implement `MochyModule` protocol, `SourceModules.walk` (parallel async + 12s timeout), `MonochromeModule` (parse FLAC `STREAMINFO`), `JioSaavnModule` (DES key `38346591`), `WebModule`.
   - Dựng `AVAudioEngine` Dual-Deck + 512KB chunk LRU cache + WebM/Opus demuxer + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`.
3. **Phase 3 — Flagship UI Shell, Metal Shaders & Core Screens (`MochyUI`):**
   - Dựng `ForceDarkTheme`, `PlayerColorExtractor`, Metal Shaders (`AmbientBackdrop`, `FrostedGlass`, `ProgressiveBlur`), `NavPill` + morphing `BottomSheetPlayer` (background zoom `.drawingGroup()`), Cover-Recede Navigation, `HomeScreen` (3 styles + SpeedDial), `SearchScreen`, `LibraryHomeScreen`, Album/Artist/Playlist screens.
4. **Phase 4 — Lyrics Engine Toàn Diện (`MochyLyrics`):**
   - Implement 14+ providers, bộ chấm điểm `pickBest` theo công thức `1_000_000 / 100_000 / 10_000 / 1_000`, TTML + Enhanced LRC parser, giao diện `LyricsGlowLine` (chữ nổi, bloom, soft-light, song ca), `CFStringTransform` romanization, Google/DeepL/OpenRouter/Mistral translate, và `LyricsAutoSync`.
5. **Phase 5 — Audio Lab, Native C++ DSP (`MochyDSP`), Crossmix & MixIt:**
   - Tích hợp C/C++17 `mochyfx` (EEL2 LiveProg) + `mochystage` (`stage_hrtf.bin`), Parametric EQ + `AutoEq`, `CoreHaptics` beat vibration, `CrossmixAnalysis`/`Planner` (19 DJ styles), và `MixItEditorSheet` dual-waveform.
6. **Phase 6 — 10 Player Styles, Player Studio, Canvas Động & Share Studio:**
   - Build `Turntable` (tua bằng tonearm), `iPod` (Click Wheel xoay + Taptic + Cover Flow), `Video` (MV sync), `Poster` (spectrum visualizer), `Timeline`, `Lyrics`, `Bedside` / `BedsideTiles`, `Module` skin renderer, `PlayerStudio` WYSIWYG, Motion Artwork (`AVPlayerLooper`), và `SongShare` xuất ảnh/MP4.
7. **Phase 7 — Importers, Sync, Cloud Backup & iOS Ecosystem Extras:**
   - Two-Way YTM Sync (`SAPISIDHASH`), Account & Link Importer (Spotify, Apple Music, Tidal, SoundCloud, CSV), `ShazamKit`, Discord Gateway Rich Presence, Last.fm/Libre.fm, iCloud/Dropbox/OneDrive/WebDAV backup, Mochy Link (`NWListener`/`NWBrowser`), WidgetKit, CarPlay, Dynamic Island Live Activities + PiP Floating Lyrics.

---

## 10. Prompt Mẫu Để Giao Việc Cho Neon (Copy Paste Sau Khi Chuyển Model)

> *"Hãy đọc kỹ toàn bộ file `MOCHY_IOS_BLUEPRINT.md` trong workspace hiện tại. Tuân thủ nghiêm ngặt mục 0 (credits Mochy Music/upstream, GPL-3.0, không paywall/ads, không hardcode secret). Hãy bắt đầu từ **Phase 1**: thiết kế cấu trúc Xcode / Swift Package Manager cho `mochy-ios`, tạo package `MochyCore`, `MochyDatabase` (GRDB schema v47 với đủ 25 bảng + 3 views), và `MochyInnerTube` (client `VISIONOS` + chuỗi fallback + `JSContext` giải cipher/`n`-param + kiểm tra `Range` byte cuối `validateStatus`), kèm unit test chạy thực tế cho `Monochrome` FLAC parser, `JioSaavn` DES decryptor và `LyricsHelper` grader."*
