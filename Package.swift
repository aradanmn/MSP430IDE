// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MSP430IDE",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MSP430IDE",
            path: "Sources/MSP430IDE",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
