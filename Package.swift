// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuotaMonitor", targets: ["QuotaMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "QuotaMonitor",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
