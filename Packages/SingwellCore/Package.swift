// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingwellCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SingwellCore", targets: ["SingwellCore"]),
    ],
    targets: [
        .target(name: "SingwellCore"),
        .testTarget(name: "SingwellCoreTests", dependencies: ["SingwellCore"]),
    ],
    swiftLanguageModes: [.v5]
)
