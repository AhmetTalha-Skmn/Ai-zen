// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalismaTakipMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CalismaTakip", targets: ["CalismaTakip"])],
    targets: [
        .target(name: "TakipCore"),
        .target(name: "CTLegacyCrypto", publicHeadersPath: "include"),
        .executableTarget(name: "CalismaTakip", dependencies: ["TakipCore", "CTLegacyCrypto"]),
        .testTarget(name: "TakipCoreTests", dependencies: ["TakipCore"]),
        .testTarget(name: "CalismaTakipTests", dependencies: ["CalismaTakip", "TakipCore"], resources: [.copy("Fixtures")])
    ]
)
