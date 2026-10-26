// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TempBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "CSensors",
            path: "Sources/CSensors",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "TempBar",
            dependencies: ["CSensors"],
            path: "Sources/TempBar"
        )
    ]
)
