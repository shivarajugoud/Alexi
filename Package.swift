// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Alexi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Alexi", targets: ["Alexi"])
    ],
    targets: [
        .executableTarget(name: "Alexi")
    ]
)
