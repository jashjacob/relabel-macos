// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Relabel",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "RelabelCore", targets: ["RelabelCore"]),
        .executable(name: "RelabelApp", targets: ["RelabelApp"]),
    ],
    targets: [
        .target(name: "RelabelCore"),
        .executableTarget(name: "RelabelApp", dependencies: ["RelabelCore"]),
        .executableTarget(name: "relabel", dependencies: ["RelabelCore"]),
        .executableTarget(name: "RelabelChecks", dependencies: ["RelabelCore"]),   // CLT has no XCTest/Testing: run with `swift run RelabelChecks`
    ]
)
