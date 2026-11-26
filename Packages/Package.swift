// swift-tools-version: 5.9
// Mochy Music iOS — Local Swift Packages
// Port of Mochy Music (https://github.com/realidkroo/Mochy-Music, GPL-3.0).

import PackageDescription

let package = Package(
    name: "MochyPackages",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MochyCore", targets: ["MochyCore"]),
        .library(name: "MochyDatabase", targets: ["MochyDatabase"]),
        .library(name: "MochyInnerTube", targets: ["MochyInnerTube"]),
        .library(name: "MochyModules", targets: ["MochyModules"]),
        .library(name: "MochyDSP", targets: ["MochyDSP"]),
        .library(name: "MochyLyrics", targets: ["MochyLyrics"]),
        .library(name: "MochyAudio", targets: ["MochyAudio"]),
        .library(name: "MochySync", targets: ["MochySync"]),
        .library(name: "MochyUI", targets: ["MochyUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "MochyCore",
            dependencies: [],
            path: "Sources/MochyCore"
        ),
        .target(
            name: "MochyDatabase",
            dependencies: [
                "MochyCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/MochyDatabase"
        ),
        .target(
            name: "MochyInnerTube",
            dependencies: [
                "MochyCore",
            ],
            path: "Sources/MochyInnerTube",
            resources: [
                .copy("Resources/solver"),
                .copy("Resources/po_token.html"),
            ]
        ),
        .target(
            name: "MochyModules",
            dependencies: [
                "MochyCore",
                "MochyInnerTube",
            ],
            path: "Sources/MochyModules"
        ),
        .target(
            name: "CMochyDSP",
            dependencies: [],
            path: "Sources/CMochyDSP",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("stage"),
            ]
        ),
        .target(
            name: "MochyDSP",
            dependencies: [
                "MochyCore",
                "CMochyDSP",
            ],
            path: "Sources/MochyDSP",
            resources: [
                .copy("Resources/stage_hrtf.bin"),
            ]
        ),
        .target(
            name: "MochyLyrics",
            dependencies: [
                "MochyCore",
                "MochyInnerTube",
            ],
            path: "Sources/MochyLyrics"
        ),
        .target(
            name: "MochyAudio",
            dependencies: [
                "MochyCore",
                "MochyDatabase",
                "MochyInnerTube",
                "MochyModules",
                "MochyDSP",
            ],
            path: "Sources/MochyAudio"
        ),
        .target(
            name: "MochySync",
            dependencies: [
                "MochyCore",
                "MochyDatabase",
                "MochyInnerTube",
            ],
            path: "Sources/MochySync"
        ),
        .target(
            name: "MochyUI",
            dependencies: [
                "MochyCore",
                "MochyDatabase",
                "MochyInnerTube",
                "MochyModules",
                "MochyDSP",
                "MochyLyrics",
                "MochyAudio",
                "MochySync",
            ],
            path: "Sources/MochyUI",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MochyCoreTests",
            dependencies: ["MochyCore"],
            path: "Tests/MochyCoreTests"
        ),
        .testTarget(
            name: "MochyDatabaseTests",
            dependencies: ["MochyDatabase", "MochyCore"],
            path: "Tests/MochyDatabaseTests"
        ),
        .testTarget(
            name: "MochyInnerTubeTests",
            dependencies: ["MochyInnerTube", "MochyCore"],
            path: "Tests/MochyInnerTubeTests"
        ),
        .testTarget(
            name: "MochyModulesTests",
            dependencies: ["MochyModules", "MochyCore", "MochyInnerTube"],
            path: "Tests/MochyModulesTests"
        ),
        .testTarget(
            name: "MochyDSPTests",
            dependencies: ["MochyDSP", "MochyCore"],
            path: "Tests/MochyDSPTests"
        ),
        .testTarget(
            name: "MochyLyricsTests",
            dependencies: ["MochyLyrics", "MochyCore", "MochyInnerTube", "MochyDatabase"],
            path: "Tests/MochyLyricsTests"
        ),
        .testTarget(
            name: "MochyAudioTests",
            dependencies: ["MochyAudio", "MochyCore", "MochyDatabase", "MochyDSP"],
            path: "Tests/MochyAudioTests"
        ),
        .testTarget(
            name: "MochySyncTests",
            dependencies: ["MochySync", "MochyCore", "MochyDatabase"],
            path: "Tests/MochySyncTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
