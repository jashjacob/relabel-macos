// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Relabel",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RelabelCore", targets: ["RelabelCore"]),
        .executable(name: "RelabelApp", targets: ["RelabelApp"]),
    ],
    targets: [
        .target(name: "RelabelCore"),
        .executableTarget(name: "RelabelApp", dependencies: ["RelabelCore"]),
    ]
)
