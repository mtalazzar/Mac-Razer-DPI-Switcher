// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RazerDPI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RazerKit", targets: ["RazerKit"]),
        .executable(name: "razerdpi", targets: ["razerdpi"]),
        .executable(name: "RazerDPIApp", targets: ["RazerDPIApp"]),
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
        .executableTarget(name: "razerdpi", dependencies: ["RazerKit"]),
        .executableTarget(name: "RazerDPIApp", dependencies: ["RazerKit"]),
        .testTarget(name: "RazerKitTests", dependencies: ["RazerKit"]),
    ]
)
