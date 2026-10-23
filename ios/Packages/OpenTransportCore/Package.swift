// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenTransportCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "OpenTransportCore", targets: ["OpenTransportCore"]),
    ],
    targets: [
        .target(name: "OpenTransportCore"),
        .testTarget(name: "OpenTransportCoreTests", dependencies: ["OpenTransportCore"]),
    ]
)
