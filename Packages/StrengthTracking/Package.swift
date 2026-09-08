// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StrengthTracking",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "StrengthTracking", targets: ["StrengthTracking"])],
    targets: [
        .target(name: "StrengthTracking"),
        .testTarget(name: "StrengthTrackingTests", dependencies: ["StrengthTracking"]),
    ]
)
