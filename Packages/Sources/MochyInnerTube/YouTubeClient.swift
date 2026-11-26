import Foundation

public struct YouTubeLocale: Sendable, Equatable {
    public let gl: String
    public let hl: String

    public init(gl: String = "US", hl: String = "en") {
        self.gl = gl
        self.hl = hl
    }
}

/// InnerTube client profiles matching Mochy Music's `YouTubeClient.kt`.
public struct YouTubeClient: Sendable, Equatable {
    public static let userAgentWeb =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    public static let originYouTube = "https://www.youtube.com"
    public static let originYouTubeMusic = "https://music.youtube.com"

    public let clientName: String
    public let clientVersion: String
    public let clientId: String
    public let userAgent: String
    public let osName: String?
    public let osVersion: String?
    public let deviceMake: String?
    public let deviceModel: String?
    public let androidSdkVersion: String?
    public let buildId: String?
    public let cronetVersion: String?
    public let packageName: String?
    public let friendlyName: String?
    public let loginSupported: Bool
    public let loginRequired: Bool
    public let useSignatureTimestamp: Bool
    public let isEmbedded: Bool
    public let useWebPoTokens: Bool
    public let apiOrigin: String
    public let apiFormatVersion: String
    public let clientScreen: String?
    public let platform: String?
    public let ownVisitorId: Bool

    public var isNativeApp: Bool {
        platform != nil
    }

    public init(
        clientName: String,
        clientVersion: String,
        clientId: String,
        userAgent: String,
        osName: String? = nil,
        osVersion: String? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        androidSdkVersion: String? = nil,
        buildId: String? = nil,
        cronetVersion: String? = nil,
        packageName: String? = nil,
        friendlyName: String? = nil,
        loginSupported: Bool = false,
        loginRequired: Bool = false,
        useSignatureTimestamp: Bool = false,
        isEmbedded: Bool = false,
        useWebPoTokens: Bool = false,
        apiOrigin: String = YouTubeClient.originYouTubeMusic,
        apiFormatVersion: String = "1",
        clientScreen: String? = nil,
        platform: String? = nil,
        ownVisitorId: Bool = false
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.clientId = clientId
        self.userAgent = userAgent
        self.osName = osName
        self.osVersion = osVersion
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.androidSdkVersion = androidSdkVersion
        self.buildId = buildId
        self.cronetVersion = cronetVersion
        self.packageName = packageName
        self.friendlyName = friendlyName
        self.loginSupported = loginSupported
        self.loginRequired = loginRequired
        self.useSignatureTimestamp = useSignatureTimestamp
        self.isEmbedded = isEmbedded
        self.useWebPoTokens = useWebPoTokens
        self.apiOrigin = apiOrigin
        self.apiFormatVersion = apiFormatVersion
        self.clientScreen = clientScreen
        self.platform = platform
        self.ownVisitorId = ownVisitorId
    }

    public func toContext(
        locale: YouTubeLocale,
        visitorData: String?,
        dataSyncId: String?
    ) -> InnerTubeContext {
        InnerTubeContext(
            client: InnerTubeContext.Client(
                clientName: clientName,
                clientVersion: clientVersion,
                clientScreen: clientScreen,
                platform: platform,
                osName: osName,
                osVersion: osVersion,
                deviceMake: deviceMake,
                deviceModel: deviceModel,
                androidSdkVersion: androidSdkVersion,
                gl: locale.gl,
                hl: locale.hl,
                visitorData: visitorData,
                utcOffsetMinutes: clientScreen != nil ? 0 : nil
            ),
            thirdParty: isEmbedded
                ? InnerTubeContext.ThirdParty(embedUrl: "\(apiOrigin)/")
                : nil,
            user: InnerTubeContext.User(
                lockedSafetyMode: false,
                onBehalfOfUser: loginSupported ? dataSyncId : nil
            )
        )
    }

    // MARK: - Client Catalog

    public static let web = YouTubeClient(
        clientName: "WEB",
        clientVersion: "2.20260708.00.00",
        clientId: "1",
        userAgent: userAgentWeb
    )

    public static let webRemix = YouTubeClient(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260707.12.00",
        clientId: "67",
        userAgent: userAgentWeb,
        loginSupported: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    public static let webCreator = YouTubeClient(
        clientName: "WEB_CREATOR",
        clientVersion: "1.20260708.06.00",
        clientId: "62",
        userAgent: userAgentWeb,
        loginSupported: true,
        loginRequired: true,
        useSignatureTimestamp: true
    )

    public static let tvHTML5 = YouTubeClient(
        clientName: "TVHTML5",
        clientVersion: "7.20260707.07.00",
        clientId: "7",
        userAgent: "Mozilla/5.0(SMART-TV; Linux; Tizen 4.0.0.2) AppleWebkit/605.1.15 (KHTML, like Gecko) SamsungBrowser/9.2 TV Safari/605.1.15",
        loginSupported: true,
        loginRequired: true,
        useSignatureTimestamp: true,
        useWebPoTokens: true
    )

    public static let tvHTML5Samsung = YouTubeClient(
        clientName: "TVHTML5",
        clientVersion: "5.20260707",
        clientId: "7",
        userAgent: "Mozilla/5.0 (SMART-TV; Linux; Tizen 2.4.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/2.4.0 TV Safari/538.1",
        osName: "Tizen",
        osVersion: "2.4.0",
        deviceMake: "Samsung",
        deviceModel: "UKS9800",
        friendlyName: "TV (Samsung)",
        apiOrigin: originYouTube,
        loginSupported: true,
        loginRequired: true,
        useSignatureTimestamp: true
    )

    public static let tvHTML5Downgraded = YouTubeClient(
        clientName: "TVHTML5",
        clientVersion: "5.20260707",
        clientId: "7",
        userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
        friendlyName: "TV (older)",
        apiOrigin: originYouTube,
        loginSupported: true,
        loginRequired: true,
        useSignatureTimestamp: true
    )

    public static let webEmbeddedPlayer = YouTubeClient(
        clientName: "WEB_EMBEDDED_PLAYER",
        clientVersion: "2.20260708.00.00",
        clientId: "56",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)",
        friendlyName: "Embedded player",
        apiOrigin: originYouTube,
        loginSupported: true,
        loginRequired: true,
        useSignatureTimestamp: true,
        isEmbedded: true
    )

    public static let tvHTML5SimplyEmbeddedPlayer = YouTubeClient(
        clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        clientVersion: "2.0",
        clientId: "85",
        userAgent: "Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15",
        loginSupported: true,
        loginRequired: false,
        useSignatureTimestamp: true,
        isEmbedded: true
    )

    public static let iOS = YouTubeClient(
        clientName: "IOS",
        clientVersion: "21.03.1",
        clientId: "5",
        userAgent: "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
        osVersion: "18.2.22C152"
    )

    public static let mobile = YouTubeClient(
        clientName: "ANDROID",
        clientVersion: "21.26.364",
        clientId: "3",
        userAgent: "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
        osName: "Android",
        osVersion: "11",
        loginSupported: true,
        useSignatureTimestamp: true
    )

    public static let androidNoSDK = YouTubeClient(
        clientName: "ANDROID",
        clientVersion: "21.26.364",
        clientId: "3",
        userAgent: "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
        osName: "Android",
        osVersion: "11",
        friendlyName: "Android No SDK",
        loginSupported: false,
        useSignatureTimestamp: false
    )

    public static let androidVRNoAuth = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Oculus Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        loginSupported: false,
        useSignatureTimestamp: false
    )

    public static let androidVR16148 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.61.48",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32",
        buildId: "SQ3A.220605.009.A1",
        cronetVersion: "132.0.6808.3",
        packageName: "com.google.android.apps.youtube.vr.oculus",
        friendlyName: "Android VR 1.61",
        loginSupported: false,
        useSignatureTimestamp: false
    )

    public static let androidVR16510 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.65.10",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        osName: "Android",
        osVersion: "12L",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32",
        buildId: "SQ3A.220605.009.A1",
        packageName: "com.google.android.apps.youtube.vr.oculus",
        friendlyName: "Android VR 1.65",
        loginSupported: false,
        useSignatureTimestamp: false
    )

    public static let androidVR14332 = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32",
        buildId: "SQ3A.220605.009.A1",
        cronetVersion: "107.0.5284.2",
        packageName: "com.google.android.apps.youtube.vr.oculus",
        friendlyName: "Android VR 1.43",
        loginSupported: false,
        useSignatureTimestamp: false
    )

    public static let androidCreator = YouTubeClient(
        clientName: "ANDROID_CREATOR",
        clientVersion: "25.03.101",
        clientId: "14",
        userAgent: "com.google.android.apps.youtube.creator/25.03.101 (Linux; U; Android 15; en_US; Pixel 9 Pro Fold; Build/AP3A.241005.015.A2; Cronet/132.0.6779.0)",
        osName: "Android",
        osVersion: "15",
        deviceMake: "Google",
        deviceModel: "Pixel 9 Pro Fold",
        androidSdkVersion: "35",
        buildId: "AP3A.241005.015.A2",
        cronetVersion: "132.0.6779.0",
        packageName: "com.google.android.apps.youtube.creator",
        friendlyName: "Android Studio",
        loginSupported: true,
        useSignatureTimestamp: true
    )

    public static let visionOS = YouTubeClient(
        clientName: "VISIONOS",
        clientVersion: "1.04",
        clientId: "101",
        userAgent: "com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)",
        osName: "visionOS",
        osVersion: "26.6.0.23O770",
        deviceMake: "Apple",
        deviceModel: "RealityDevice17,1",
        friendlyName: "visionOS",
        apiOrigin: originYouTube,
        apiFormatVersion: "2",
        clientScreen: "WATCH",
        platform: "MOBILE",
        ownVisitorId: true,
        loginSupported: false,
        useSignatureTimestamp: false
    )

    public static let iPadOS = YouTubeClient(
        clientName: "IOS",
        clientVersion: "21.03.3",
        clientId: "5",
        userAgent: "com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)",
        osName: "iPadOS",
        osVersion: "17.7.10.21H450",
        deviceMake: "Apple",
        deviceModel: "iPad7,6",
        friendlyName: "iPadOS",
        loginSupported: false,
        useSignatureTimestamp: false,
        packageName: "com.google.ios.youtube"
    )

    // MARK: - Resolution Chains (matching YTPlayerUtils.kt)

    public static let mainClient = visionOS
    public static let metadataClient = webRemix

    public static let accountClients: [YouTubeClient] = [
        tvHTML5Samsung,
        webEmbeddedPlayer,
        tvHTML5Downgraded,
    ]

    public static let streamFallbackClients: [YouTubeClient] = [
        visionOS,
        webRemix,
        web,
        webCreator,
        iPadOS,
        androidVR14332,
        androidVR16148,
        androidVR16510,
        androidVRNoAuth,
        tvHTML5SimplyEmbeddedPlayer,
        tvHTML5,
        androidCreator,
        mobile,
    ]
}
