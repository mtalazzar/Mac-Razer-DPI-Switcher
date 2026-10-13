// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DPISwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RazerKit", targets: ["RazerKit"]),
        .executable(name: "dpiswitcher", targets: ["dpiswitcher"]),
        .executable(name: "DPISwitcherApp", targets: ["DPISwitcherApp"]),
    ],
    targets: [
        .target(
            name: "CRazerUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "RazerKit",
            dependencies: ["CRazerUSB"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "dpiswitcher", dependencies: ["RazerKit"]),
        .executableTarget(name: "DPISwitcherApp", dependencies: ["RazerKit"]),
        .testTarget(name: "RazerKitTests", dependencies: ["RazerKit"]),
    ]
)
