// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AFMChat",
    platforms: [.macOS("27.0")],
    products: [.library(name: "AFMChatCore", targets: ["AFMChatCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "AFMChatCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "AFMChatProbe", dependencies: ["AFMChatCore"], path: "tools/AFMChatProbe"),
        .testTarget(name: "AFMChatCoreTests", dependencies: ["AFMChatCore"])
    ]
)
