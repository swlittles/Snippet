// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Snippet", platforms: [.macOS(.v13)],
    products: [.executable(name: "Snippet", targets: ["Snippet"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [.executableTarget(name: "Snippet", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])]
)
