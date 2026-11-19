// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DrinkTrackerCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "DrinkTrackerCore", targets: ["DrinkTrackerCore"])],
    targets: [
        .target(name: "DrinkTrackerCore"),
        .testTarget(name: "DrinkTrackerCoreTests", dependencies: ["DrinkTrackerCore"])
    ]
)
