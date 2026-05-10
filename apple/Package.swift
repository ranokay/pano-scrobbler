// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PanoScrobbler",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PanoScrobbler", targets: ["PanoScrobbler"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Services", targets: ["Services"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "MacIntegration", targets: ["MacIntegration"])
    ],
    targets: [
        .target(
            name: "Core",
            path: "Packages/Core/Sources"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Packages/Core/Tests"
        ),
        .target(
            name: "Services",
            dependencies: ["Core"],
            path: "Packages/Services/Sources"
        ),
        .testTarget(
            name: "ServicesTests",
            dependencies: ["Services"],
            path: "Packages/Services/Tests"
        ),
        .target(
            name: "Persistence",
            dependencies: ["Core"],
            path: "Packages/Persistence/Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            path: "Packages/Persistence/Tests"
        ),
        .target(
            name: "MacIntegration",
            dependencies: [
                "Core",
                "Services"
            ],
            path: "Packages/MacIntegration/Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "PanoScrobbler",
            dependencies: [
                "Core",
                "Services",
                "Persistence",
                "MacIntegration"
            ],
            path: "Apps/macOS",
            exclude: ["PanoScrobbler.entitlements"],
            sources: ["Sources"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
