// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "macos-glass-designer",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "macos-glass-designer", targets: ["GlassDesigner"])],
  targets: [
    .target(name: "GlassBridge", publicHeadersPath: "include"),
    .target(
      name: "GlassDesign", dependencies: ["GlassBridge"], resources: [.copy("Resources/Fonts")]),
    .executableTarget(name: "GlassDesigner", dependencies: ["GlassDesign"]),
    .testTarget(name: "GlassDesignTests", dependencies: ["GlassDesign"]),
  ]
)
