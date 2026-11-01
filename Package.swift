// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoType",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AutoTypeCore", targets: ["AutoTypeCore"]),
        .executable(name: "AutoTypeIME", targets: ["AutoTypeIME"]),
        .executable(name: "AutoTypeSettings", targets: ["AutoTypeSettings"]),
    ],
    targets: [
        .target(
            name: "AutoTypeCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AutoTypeIME",
            dependencies: ["AutoTypeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AutoTypeSettings",
            dependencies: ["AutoTypeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AutoTypeChecks",
            dependencies: ["AutoTypeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AutoTypeCoreTests",
            dependencies: ["AutoTypeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // The Command Line Tools toolchain ships the swift-testing
                // framework outside the usual search path.
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
