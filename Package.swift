// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoLang",
    platforms: [
        .macOS(.v13) // SMAppService login-item API + modern TIS behavior
    ],
    targets: [
        .executableTarget(
            name: "AutoLang",
            path: "Sources/AutoLang",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),      // TIS input-source APIs, UCKeyTranslate
                .linkedFramework("CoreGraphics") // CGEventTap
            ]
        )
    ]
)
