// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShortcutKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ShortcutKit", targets: ["ShortcutKit"]),
        .library(name: "ShortcutKitUI", targets: ["ShortcutKitUI"]),
        .library(name: "ShortcutKitGlobal", targets: ["ShortcutKitGlobal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nielsmadan/ShortcutField", from: "2.1.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ShortcutKit",
            dependencies: [
                .product(name: "ShortcutField", package: "ShortcutField"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .target(
            name: "ShortcutKitUI",
            dependencies: [
                "ShortcutKit",
                .product(name: "ShortcutField", package: "ShortcutField"),
            ]
        ),
        .target(
            name: "ShortcutKitGlobal",
            dependencies: ["ShortcutKit"]
        ),
        .testTarget(name: "ShortcutKitTests", dependencies: ["ShortcutKit"]),
        .testTarget(
            name: "ShortcutKitUITests",
            dependencies: ["ShortcutKitUI", "ShortcutKit"],
            path: "Tests/ShortcutKitUITests"
        ),
        .testTarget(name: "ShortcutKitGlobalTests", dependencies: ["ShortcutKitGlobal"]),
    ]
)
