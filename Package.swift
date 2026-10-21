// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftScanKit",
    platforms: [.iOS(.v15)],
    products: [.library(name: "SwiftScanKit", targets: ["SwiftScanKit"])],
    targets: [
        .target(
            name: "SwiftScanKit",
            path: "Sources/SwiftScanKit",
            exclude: ["Info.plist", "SwiftScanKit.h"],
            resources: [.process("Media.xcassets")]
        )
    ]
)
