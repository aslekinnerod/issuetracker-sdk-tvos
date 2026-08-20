// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IssuetrackerTVSDK",
    platforms: [.tvOS(.v17)],
    products: [
        .library(name: "IssuetrackerTVSDK", targets: ["IssuetrackerTVSDK"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "IssuetrackerTVSDK"),
        .testTarget(
            name: "IssuetrackerTVSDKTests",
            dependencies: ["IssuetrackerTVSDK"]
        ),
    ]
)
