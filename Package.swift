// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MintFiles",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MintFiles", targets: ["MintFiles"])],
    targets: [.executableTarget(name: "MintFiles", path: "Sources")]
)
