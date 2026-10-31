// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuBarCalendar",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MenuBarCalendar",
            path: "Sources/MenuBarCalendar",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
