// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProcessLink",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "ProcessLinkKit"),
        .executableTarget(
            name: "ProcessLink",
            dependencies: ["ProcessLinkKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ProcessLinkKitTests", dependencies: ["ProcessLinkKit"]),
    ]
)
