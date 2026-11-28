import Foundation
import Observation

// MARK: - Parity Enums (Mochy Music PreferenceKeys / Enums)

public enum AudioQuality: String, CaseIterable, Codable, Sendable {
    case auto
    case low
    case medium
    case high

    public var maxBitrate: Int? {
        switch self {
        case .low: return 70_000
        case .medium: return 135_000
        case .high, .auto: return nil
        }
    }
}

public enum PlayerStyle: String, CaseIterable, Codable, Sendable {
    case flagship = "FLAGSHIP"
    case turntable = "TURNTABLE"
    case video = "VIDEO"
    case ipod = "IPOD"
    case poster = "POSTER"
    case timeline = "TIMELINE"
    case lyrics = "LYRICS"
    case bedside = "BEDSIDE"
    case bedsideTiles = "BEDSIDE_TILES"
    case module = "MODULE"

    public var displayName: String {
        switch self {
        case .flagship: return "Flagship"
        case .turntable: return "Turntable"
        case .video: return "Video"
        case .ipod: return "iPod Classic"
        case .poster: return "Poster"
        case .timeline: return "Timeline"
        case .lyrics: return "Lyrics Stage"
        case .bedside: return "Bedside Clock"
        case .bedsideTiles: return "Bedside Tiles"
        case .module: return "Module Skin"
        }
    }
}

public enum HomeStyle: String, CaseIterable, Codable, Sendable {
    case mochyy = "MOCHYY"
    case listenNow = "LISTEN_NOW"
    case hopIn = "HOP_IN"
}

public enum PlaylistStyle: String, CaseIterable, Codable, Sendable {
    case classic = "CLASSIC"
    case modern = "MODERN"
    case editorial = "EDITORIAL"
    case poster = "POSTER"
    case minimal = "MINIMAL"
    case cards = "CARDS"
}

public enum FlagshipBackground: String, CaseIterable, Codable, Sendable {
    case coverGradient = "COVER_GRADIENT"
    case solid = "SOLID"
    case darkGradient = "DARK_GRADIENT"
    case appleMusic = "APPLE_MUSIC"
    case ambient = "AMBIENT"
}

public enum SeekbarStyle: String, CaseIterable, Codable, Sendable {
    case `default` = "DEFAULT"
    case wavy = "WAVY"
    case slim = "SLIM"
}

public enum TransportLayout: String, CaseIterable, Codable, Sendable {
    case three = "THREE"
    case tenSeconds = "TEN_SECONDS"
    case queueRepeat = "QUEUE_REPEAT"
}

public enum IpodTheme: String, CaseIterable, Codable, Sendable {
    case silver = "SILVER"
    case black = "BLACK"
    case u2 = "U2"
    case trueDark = "TRUE_DARK"
}

public enum BedsideClockStyle: String, CaseIterable, Codable, Sendable {
    case big = "BIG"
    case stacked = "STACKED"
    case analog = "ANALOG"
    case cover = "COVER"
}

public enum BlurQuality: String, CaseIterable, Codable, Sendable {
    case low = "LOW"
    case high = "HIGH"
}

public enum PlayerCoverStyle: String, CaseIterable, Codable, Sendable {
    case classic
    case full
    case minimal
    case fade
    case canvas
    case carousel
}

public enum LyricsMotionStyle: String, CaseIterable, Codable, Sendable {
    case glide
    case classic
    case neon
}

public enum CrossmixMode: String, CaseIterable, Codable, Sendable {
    case off
    case classic
    case mixit
}

public enum DensityScale: String, CaseIterable, Codable, Sendable {
    case compact
    case normal
    case comfortable

    public var multiplier: Double {
        switch self {
        case .compact: return 0.85
        case .normal: return 1.0
        case .comfortable: return 1.15
        }
    }
}

public enum StreamBackend: String, CaseIterable, Codable, Sendable {
    case youtube
    case monochrome
    case jiosaavn
    case appleMusic
}

/// Whitelisted theme/layout keys that external `ModuleSkin` definitions may override safely.
public enum LookSettingKey: String, CaseIterable, Codable, Sendable {
    case playerStyle
    case homeStyle
    case playlistStyle
    case thumbnailCornerRadius
    case lyricsMotionStyle
    case blur
    case blurQuality
    case blurStrengthPx
    case enableProgressiveBlur
    case elementBlur
    case pureBlack
    case accentColor
    case dynamicTheme
    case playerBackground
    case flagshipBackground
    case ipodTheme
    case ipodWheelColor
    case bottomBar
}

// MARK: - Preference Keys

public enum PreferenceKeys {
    public static let audioQuality = "audioQuality"
    public static let playerStyle = "playerStyle"
    public static let homeStyle = "homeStyle"
    public static let playlistStyle = "playlistStyle"
    public static let flagshipBackground = "flagshipBackground"
    public static let seekbarStyle = "seekbarStyle"
    public static let transportLayout = "transportLayout"
    public static let ipodTheme = "ipodTheme"
    public static let ipodTallScreen = "ipodTallScreen"
    public static let bedsideClockStyle = "bedsideClockStyle"
    public static let bedsideNightTint = "bedsideNightTint"
    public static let blurQuality = "blurQuality"
    public static let pureBlack = "pureBlack"
    public static let thumbnailCornerRadius = "thumbnailCornerRadius"
    public static let playerControlsShift = "playerControlsShift"
    public static let playerCardGrowth = "playerCardGrowth"
    public static let playerCoverStyle = "playerCoverStyle"
    public static let lyricsMotionStyle = "lyricsMotionStyle"
    public static let crossmixMode = "crossmixMode"
    public static let crossmixDurationMs = "crossmixDurationMs"
    public static let densityScale = "densityScale"
    public static let streamBackend = "streamBackend"
    public static let preferMp4OnIOS = "preferMp4OnIOS"
    public static let audioPassEnabled = "audioPassEnabled"
    public static let dspEqEnabled = "dspEqEnabled"
    public static let dspStageEnabled = "dspStageEnabled"
    public static let dspOrbitEnabled = "dspOrbitEnabled"
    public static let hapticsEnabled = "hapticsEnabled"
    public static let lyricsRomanize = "lyricsRomanize"
    public static let lyricsTranslate = "lyricsTranslate"
    public static let lyricsOrderOverride = "lyricsOrderOverride"
    public static let offlineMode = "offlineMode"
    public static let sourceOrder = "sourceOrder"
    public static let canvasOrder = "canvasOrder"
    public static let ytExcludeImports = "ytExcludeImports"
    public static let useProxy = "useProxy"
    public static let proxyUrl = "proxyUrl"
    public static let innerTubeCookie = "innerTubeCookie"
    public static let visitorData = "visitorData"
    public static let dataSyncId = "dataSyncId"
    public static let countryCode = "countryCode"
    public static let languageCode = "languageCode"
    public static let infiniteQueueEnabled = "infiniteQueueEnabled"
    public static let loudnessNormalizationEnabled = "loudnessNormalizationEnabled"
    public static let lyricsTranslationLanguage = "lyricsTranslationLanguage"
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let profileUsername = "profileUsername"
    public static let profileCardNumber = "profileCardNumber"
    public static let profileJoinedTimestamp = "profileJoinedTimestamp"
    public static let profileAvatarPath = "profileAvatarPath"
    public static let customMonochromeServers = "customMonochromeServers"
    public static let webModuleURLs = "webModuleURLs"
    public static let settingsSchemaVersion = "settingsSchemaVersion"
}

// MARK: - Observable Settings Store

@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    public var audioQuality: AudioQuality {
        didSet { defaults.set(audioQuality.rawValue, forKey: PreferenceKeys.audioQuality) }
    }
    public var playerStyle: PlayerStyle {
        didSet { defaults.set(playerStyle.rawValue, forKey: PreferenceKeys.playerStyle) }
    }
    public var homeStyle: HomeStyle {
        didSet { defaults.set(homeStyle.rawValue, forKey: PreferenceKeys.homeStyle) }
    }
    public var playlistStyle: PlaylistStyle {
        didSet { defaults.set(playlistStyle.rawValue, forKey: PreferenceKeys.playlistStyle) }
    }
    public var flagshipBackground: FlagshipBackground {
        didSet { defaults.set(flagshipBackground.rawValue, forKey: PreferenceKeys.flagshipBackground) }
    }
    public var seekbarStyle: SeekbarStyle {
        didSet { defaults.set(seekbarStyle.rawValue, forKey: PreferenceKeys.seekbarStyle) }
    }
    public var transportLayout: TransportLayout {
        didSet { defaults.set(transportLayout.rawValue, forKey: PreferenceKeys.transportLayout) }
    }
    public var ipodTheme: IpodTheme {
        didSet { defaults.set(ipodTheme.rawValue, forKey: PreferenceKeys.ipodTheme) }
    }
    public var ipodTallScreen: Bool {
        didSet { defaults.set(ipodTallScreen, forKey: PreferenceKeys.ipodTallScreen) }
    }
    public var bedsideClockStyle: BedsideClockStyle {
        didSet { defaults.set(bedsideClockStyle.rawValue, forKey: PreferenceKeys.bedsideClockStyle) }
    }
    public var bedsideNightTint: Bool {
        didSet { defaults.set(bedsideNightTint, forKey: PreferenceKeys.bedsideNightTint) }
    }
    public var blurQuality: BlurQuality {
        didSet { defaults.set(blurQuality.rawValue, forKey: PreferenceKeys.blurQuality) }
    }
    public var pureBlack: Bool {
        didSet { defaults.set(pureBlack, forKey: PreferenceKeys.pureBlack) }
    }
    public var thumbnailCornerRadius: Double {
        didSet { defaults.set(thumbnailCornerRadius, forKey: PreferenceKeys.thumbnailCornerRadius) }
    }
    public var playerControlsShift: Double {
        didSet { defaults.set(playerControlsShift, forKey: PreferenceKeys.playerControlsShift) }
    }
    public var playerCardGrowth: Double {
        didSet { defaults.set(playerCardGrowth, forKey: PreferenceKeys.playerCardGrowth) }
    }
    public var playerCoverStyle: PlayerCoverStyle {
        didSet { defaults.set(playerCoverStyle.rawValue, forKey: PreferenceKeys.playerCoverStyle) }
    }
    public var lyricsMotionStyle: LyricsMotionStyle {
        didSet { defaults.set(lyricsMotionStyle.rawValue, forKey: PreferenceKeys.lyricsMotionStyle) }
    }
    public var crossmixMode: CrossmixMode {
        didSet { defaults.set(crossmixMode.rawValue, forKey: PreferenceKeys.crossmixMode) }
    }
    public var crossmixDurationMs: Int {
        didSet { defaults.set(crossmixDurationMs, forKey: PreferenceKeys.crossmixDurationMs) }
    }
    public var densityScale: DensityScale {
        didSet { defaults.set(densityScale.rawValue, forKey: PreferenceKeys.densityScale) }
    }
    public var streamBackend: StreamBackend {
        didSet { defaults.set(streamBackend.rawValue, forKey: PreferenceKeys.streamBackend) }
    }
    public var preferMp4OnIOS: Bool {
        didSet { defaults.set(preferMp4OnIOS, forKey: PreferenceKeys.preferMp4OnIOS) }
    }
    public var audioPassEnabled: Bool {
        didSet { defaults.set(audioPassEnabled, forKey: PreferenceKeys.audioPassEnabled) }
    }
    public var dspEqEnabled: Bool {
        didSet { defaults.set(dspEqEnabled, forKey: PreferenceKeys.dspEqEnabled) }
    }
    public var dspStageEnabled: Bool {
        didSet { defaults.set(dspStageEnabled, forKey: PreferenceKeys.dspStageEnabled) }
    }
    public var dspOrbitEnabled: Bool {
        didSet { defaults.set(dspOrbitEnabled, forKey: PreferenceKeys.dspOrbitEnabled) }
    }
    public var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: PreferenceKeys.hapticsEnabled) }
    }
    public var lyricsRomanize: Bool {
        didSet { defaults.set(lyricsRomanize, forKey: PreferenceKeys.lyricsRomanize) }
    }
    public var lyricsTranslate: Bool {
        didSet { defaults.set(lyricsTranslate, forKey: PreferenceKeys.lyricsTranslate) }
    }
    public var lyricsOrderOverride: Bool {
        didSet { defaults.set(lyricsOrderOverride, forKey: PreferenceKeys.lyricsOrderOverride) }
    }
    public var offlineMode: Bool {
        didSet { defaults.set(offlineMode, forKey: PreferenceKeys.offlineMode) }
    }
    public var sourceOrder: [String] {
        didSet { defaults.set(sourceOrder, forKey: PreferenceKeys.sourceOrder) }
    }
    public var canvasOrder: [String] {
        didSet { defaults.set(canvasOrder, forKey: PreferenceKeys.canvasOrder) }
    }
    public var ytExcludeImports: Bool {
        didSet { defaults.set(ytExcludeImports, forKey: PreferenceKeys.ytExcludeImports) }
    }
    public var infiniteQueueEnabled: Bool {
        didSet { defaults.set(infiniteQueueEnabled, forKey: PreferenceKeys.infiniteQueueEnabled) }
    }
    public var loudnessNormalizationEnabled: Bool {
        didSet { defaults.set(loudnessNormalizationEnabled, forKey: PreferenceKeys.loudnessNormalizationEnabled) }
    }
    public var lyricsTranslationLanguage: String {
        didSet { defaults.set(lyricsTranslationLanguage, forKey: PreferenceKeys.lyricsTranslationLanguage) }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: PreferenceKeys.hasCompletedOnboarding) }
    }
    public var profileUsername: String {
        didSet { defaults.set(profileUsername, forKey: PreferenceKeys.profileUsername) }
    }
    public var profileCardNumber: String {
        didSet { defaults.set(profileCardNumber, forKey: PreferenceKeys.profileCardNumber) }
    }
    public var profileJoinedTimestamp: TimeInterval {
        didSet { defaults.set(profileJoinedTimestamp, forKey: PreferenceKeys.profileJoinedTimestamp) }
    }
    public var profileAvatarPath: String? {
        didSet { defaults.set(profileAvatarPath, forKey: PreferenceKeys.profileAvatarPath) }
    }
    public var customMonochromeServers: [String] {
        didSet { defaults.set(customMonochromeServers, forKey: PreferenceKeys.customMonochromeServers) }
    }
    public var webModuleURLs: [String] {
        didSet { defaults.set(webModuleURLs, forKey: PreferenceKeys.webModuleURLs) }
    }
    public var countryCode: String {
        didSet { defaults.set(countryCode, forKey: PreferenceKeys.countryCode) }
    }
    public var languageCode: String {
        didSet { defaults.set(languageCode, forKey: PreferenceKeys.languageCode) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.audioQuality = Self.decodeEnum(defaults, key: PreferenceKeys.audioQuality, fallback: .high)
        self.playerStyle = Self.decodeEnum(defaults, key: PreferenceKeys.playerStyle, fallback: .flagship)
        self.homeStyle = Self.decodeEnum(defaults, key: PreferenceKeys.homeStyle, fallback: .mochyy)
        self.playlistStyle = Self.decodeEnum(defaults, key: PreferenceKeys.playlistStyle, fallback: .modern)
        self.flagshipBackground = Self.decodeEnum(defaults, key: PreferenceKeys.flagshipBackground, fallback: .appleMusic)
        self.seekbarStyle = Self.decodeEnum(defaults, key: PreferenceKeys.seekbarStyle, fallback: .default)
        self.transportLayout = Self.decodeEnum(defaults, key: PreferenceKeys.transportLayout, fallback: .three)
        self.ipodTheme = Self.decodeEnum(defaults, key: PreferenceKeys.ipodTheme, fallback: .silver)
        self.ipodTallScreen = defaults.bool(forKey: PreferenceKeys.ipodTallScreen)
        self.bedsideClockStyle = Self.decodeEnum(defaults, key: PreferenceKeys.bedsideClockStyle, fallback: .big)
        self.bedsideNightTint = Self.decodeBool(defaults, key: PreferenceKeys.bedsideNightTint, default: true)
        self.blurQuality = Self.decodeEnum(defaults, key: PreferenceKeys.blurQuality, fallback: .high)
        self.pureBlack = Self.decodeBool(defaults, key: PreferenceKeys.pureBlack, default: true)
        let savedRadius = defaults.object(forKey: PreferenceKeys.thumbnailCornerRadius) as? Double
        self.thumbnailCornerRadius = savedRadius ?? 14.0
        self.playerControlsShift = defaults.double(forKey: PreferenceKeys.playerControlsShift)
        self.playerCardGrowth = defaults.double(forKey: PreferenceKeys.playerCardGrowth)
        self.playerCoverStyle = Self.decodeEnum(defaults, key: PreferenceKeys.playerCoverStyle, fallback: .full)
        self.lyricsMotionStyle = Self.decodeEnum(defaults, key: PreferenceKeys.lyricsMotionStyle, fallback: .glide)
        self.crossmixMode = Self.decodeEnum(defaults, key: PreferenceKeys.crossmixMode, fallback: .classic)
        let savedDuration = defaults.integer(forKey: PreferenceKeys.crossmixDurationMs)
        self.crossmixDurationMs = savedDuration > 0 ? savedDuration : 6000
        self.densityScale = Self.decodeEnum(defaults, key: PreferenceKeys.densityScale, fallback: .normal)
        self.streamBackend = Self.decodeEnum(defaults, key: PreferenceKeys.streamBackend, fallback: .youtube)
        self.preferMp4OnIOS = Self.decodeBool(defaults, key: PreferenceKeys.preferMp4OnIOS, default: true)
        self.audioPassEnabled = defaults.bool(forKey: PreferenceKeys.audioPassEnabled)
        self.dspEqEnabled = defaults.bool(forKey: PreferenceKeys.dspEqEnabled)
        self.dspStageEnabled = defaults.bool(forKey: PreferenceKeys.dspStageEnabled)
        self.dspOrbitEnabled = defaults.bool(forKey: PreferenceKeys.dspOrbitEnabled)
        self.hapticsEnabled = defaults.bool(forKey: PreferenceKeys.hapticsEnabled)
        self.lyricsRomanize = Self.decodeBool(defaults, key: PreferenceKeys.lyricsRomanize, default: true)
        self.lyricsTranslate = defaults.bool(forKey: PreferenceKeys.lyricsTranslate)
        self.lyricsOrderOverride = defaults.bool(forKey: PreferenceKeys.lyricsOrderOverride)
        self.offlineMode = defaults.bool(forKey: PreferenceKeys.offlineMode)
        self.sourceOrder = defaults.stringArray(forKey: PreferenceKeys.sourceOrder)
            ?? ["youtube", "monochrome", "jiosaavn"]
        self.canvasOrder = defaults.stringArray(forKey: PreferenceKeys.canvasOrder)
            ?? ["appleMusic", "monochrome", "spotify", "artistVideo"]
        self.ytExcludeImports = Self.decodeBool(defaults, key: PreferenceKeys.ytExcludeImports, default: true)
        self.infiniteQueueEnabled = Self.decodeBool(defaults, key: PreferenceKeys.infiniteQueueEnabled, default: true)
        self.loudnessNormalizationEnabled = Self.decodeBool(defaults, key: PreferenceKeys.loudnessNormalizationEnabled, default: true)
        self.lyricsTranslationLanguage = defaults.string(forKey: PreferenceKeys.lyricsTranslationLanguage) ?? "vi"
        self.hasCompletedOnboarding = defaults.bool(forKey: PreferenceKeys.hasCompletedOnboarding)
        self.profileUsername = defaults.string(forKey: PreferenceKeys.profileUsername) ?? ""
        if let existingCard = defaults.string(forKey: PreferenceKeys.profileCardNumber), !existingCard.isEmpty {
            self.profileCardNumber = existingCard
        } else {
            let generated = String(format: "%04d%04d", Int.random(in: 1000...9999), Int.random(in: 1000...9999))
            defaults.set(generated, forKey: PreferenceKeys.profileCardNumber)
            self.profileCardNumber = generated
        }
        let savedJoined = defaults.double(forKey: PreferenceKeys.profileJoinedTimestamp)
        if savedJoined > 0 {
            self.profileJoinedTimestamp = savedJoined
        } else {
            let now = Date().timeIntervalSince1970
            defaults.set(now, forKey: PreferenceKeys.profileJoinedTimestamp)
            self.profileJoinedTimestamp = now
        }
        self.profileAvatarPath = defaults.string(forKey: PreferenceKeys.profileAvatarPath)
        self.customMonochromeServers = defaults.stringArray(forKey: PreferenceKeys.customMonochromeServers) ?? []
        self.webModuleURLs = defaults.stringArray(forKey: PreferenceKeys.webModuleURLs) ?? []
        let savedCountry = defaults.string(forKey: PreferenceKeys.countryCode)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = (savedCountry?.isEmpty == false ? savedCountry! : "VN")
        let savedLang = defaults.string(forKey: PreferenceKeys.languageCode)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.languageCode = (savedLang?.isEmpty == false ? savedLang! : "vi")

        let schemaVer = defaults.integer(forKey: PreferenceKeys.settingsSchemaVersion)
        if schemaVer < 2 {
            if self.seekbarStyle == .wavy {
                self.seekbarStyle = .default
                defaults.set(SeekbarStyle.default.rawValue, forKey: PreferenceKeys.seekbarStyle)
            }
            if self.sourceOrder == ["monochrome", "jiosaavn", "youtube"] {
                self.sourceOrder = ["youtube", "monochrome", "jiosaavn"]
                defaults.set(self.sourceOrder, forKey: PreferenceKeys.sourceOrder)
            }
            defaults.set(2, forKey: PreferenceKeys.settingsSchemaVersion)
        }
        if schemaVer < 3 {
            if self.playerCoverStyle == .classic {
                self.playerCoverStyle = .full
                defaults.set(PlayerCoverStyle.full.rawValue, forKey: PreferenceKeys.playerCoverStyle)
            }
            defaults.set(3, forKey: PreferenceKeys.settingsSchemaVersion)
        }
    }

    private static func decodeEnum<T: RawRepresentable>(
        _ defaults: UserDefaults,
        key: String,
        fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else {
            return fallback
        }
        return value
    }

    private static func decodeBool(_ defaults: UserDefaults, key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : defaultValue
    }
}
