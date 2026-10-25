import AppKit
import XCTest

@testable import GlassDesign

final class BackdropTests: XCTestCase {
  /// Rec. 709 luma statistics, sampled across the whole image.
  private struct Luma {
    let mean: Double
    let deviation: Double
    let samples: [Double]
  }

  private func luma(_ image: CGImage) throws -> Luma {
    let width = 96
    let height = max(1, image.height * width / image.width)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
    let samples = (0..<width * height).map { index in
      (0.2126 * Double(bytes[index * 4]) + 0.7152 * Double(bytes[index * 4 + 1])
        + 0.0722 * Double(bytes[index * 4 + 2])) / 255
    }
    let mean = samples.reduce(0, +) / Double(samples.count)
    let variance = samples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(samples.count)
    return Luma(mean: mean, deviation: variance.squareRoot(), samples: samples)
  }

  @MainActor private func wallpaper(_ name: String) throws -> Wallpaper {
    try XCTUnwrap(Wallpapers.installed().first { $0.name == name }, "\(name) is installed")
  }

  @MainActor func testInstalledWallpapersStartWithTheCurrentDesktopAndSkipFlatColors() throws {
    let wallpapers = Wallpapers.installed()
    let current = try XCTUnwrap(NSWorkspace.shared.desktopImageURL(for: XCTUnwrap(NSScreen.main)))
    XCTAssertEqual(wallpapers.first?.url.standardizedFileURL, current.standardizedFileURL)
    XCTAssertTrue(wallpapers.contains { $0.name == "Sonoma" })
    XCTAssertFalse(wallpapers.contains { $0.url.path.contains("Solid Colors") })
    XCTAssertEqual(Set(wallpapers.map(\.url.standardizedFileURL)).count, wallpapers.count)
  }

  @MainActor func testDynamicWallpapersFollowTheThemeAndOthersStayTheSame() throws {
    let sonoma = try wallpaper("Sonoma")
    let light = try XCTUnwrap(Wallpapers.decode(sonoma, dark: false, maxPixelSize: 256))
    let dark = try XCTUnwrap(Wallpapers.decode(sonoma, dark: true, maxPixelSize: 256))
    XCTAssertEqual(max(light.width, light.height), 256, "Wallpapers are downsampled")
    XCTAssertGreaterThan(try luma(light).mean, try luma(dark).mean + 0.1)
    let blue = try wallpaper("iMac Blue")
    let blueLight = try XCTUnwrap(Wallpapers.decode(blue, dark: false, maxPixelSize: 128))
    let blueDark = try XCTUnwrap(Wallpapers.decode(blue, dark: true, maxPixelSize: 128))
    XCTAssertEqual(try luma(blueLight).samples, try luma(blueDark).samples)
    XCTAssertNil(
      Wallpapers.decode(
        Wallpaper(name: "Missing", url: URL(fileURLWithPath: "/nonexistent.heic")), dark: false,
        maxPixelSize: 64))
  }

  @MainActor private func render(_ view: NSView) throws -> CGImage {
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return try XCTUnwrap(bitmap.cgImage)
  }

  @MainActor func testScenesAreTexturedDistinctAndFollowTheTheme() async throws {
    let backdrop = BackdropView(frame: CGRect(x: 0, y: 0, width: 870, height: 860))
    backdrop.wallpaper = try wallpaper("Sonoma")
    var lights: [BackdropScene: Luma] = [:]
    for scene in BackdropScene.allCases {
      var byTheme: [BackdropTheme: Luma] = [:]
      for theme in BackdropTheme.allCases {
        backdrop.scene = scene
        backdrop.theme = theme
        try await waitUntil("\(scene) \(theme) images") { backdrop.pendingImages == 0 }
        let stats = try luma(render(backdrop))
        // Flat fills measure 0; a text-heavy editor measures about 0.07.
        XCTAssertGreaterThan(stats.deviation, 0.05, "\(scene) \(theme) must not be flat")
        byTheme[theme] = stats
      }
      let light = try XCTUnwrap(byTheme[.light])
      let dark = try XCTUnwrap(byTheme[.dark])
      XCTAssertGreaterThan(light.mean, dark.mean + 0.15, "\(scene) must follow the theme")
      lights[scene] = light
    }
    for (a, b) in zip(BackdropScene.allCases, BackdropScene.allCases.dropFirst()) {
      let difference =
        zip(try XCTUnwrap(lights[a]).samples, try XCTUnwrap(lights[b]).samples)
        .map { abs($0 - $1) }.reduce(0, +) / Double(try XCTUnwrap(lights[a]).samples.count)
      XCTAssertGreaterThan(difference, 0.05, "\(a) and \(b) must look different")
    }
  }

  /// Every scene window uses the unified compact title bar AppKit draws (measured on macOS 26):
  /// 40 pt tall, with 14 pt window buttons 23 pt apart, centred in the bar.
  @MainActor func testSceneWindowsShareTheSystemCompactTitleBar() async throws {
    let backdrop = BackdropView(frame: CGRect(x: 0, y: 0, width: 870, height: 860))
    backdrop.wallpaper = try wallpaper("iMac Blue")
    var found = 0
    for scene in BackdropScene.allCases {
      for theme in BackdropTheme.allCases {
        backdrop.scene = scene
        backdrop.theme = theme
        try await waitUntil("\(scene) \(theme) images") { backdrop.pendingImages == 0 }
        let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        let image = try Pixels(bitmap)
        let scale = Double(bitmap.pixelsWide) / backdrop.bounds.width
        let buttons = image.closeButtons(scale: scale)
        XCTAssertFalse(buttons.isEmpty, "\(scene) \(theme) draws a window")
        for button in buttons {
          let label = "\(scene) \(theme) window at \(button)"
          XCTAssertEqual(button.width / scale, 14, accuracy: 1, label)
          let bar = image.titleBar(beside: button)
          XCTAssertEqual(Double(bar.count) / scale, 40, accuracy: 1, label)
          XCTAssertEqual(
            button.midY, Double(bar.lowerBound + bar.upperBound) / 2, accuracy: scale, label)
          found += 1
        }
      }
    }
    XCTAssertEqual(found, 10, "Desktop has two windows; every other scene has one, in both themes")
  }

  /// Photos decode in the background, so a scene first draws before any are loaded.
  @MainActor func testScenesDrawBeforeTheirImagesLoad() throws {
    for scene in [BackdropScene.photos, .desktop, .article] {
      let backdrop = BackdropView(frame: CGRect(x: 0, y: 0, width: 870, height: 860))
      backdrop.wallpaper = try wallpaper("iMac Blue")
      backdrop.scene = scene
      XCTAssertGreaterThan(backdrop.pendingImages, 0, "\(scene) is still loading")
      XCTAssertGreaterThan(
        try luma(render(backdrop)).deviation, 0.01, "\(scene) draws its layout, not a blank")
    }
  }

  @MainActor func testUnreadableWallpaperIsReported() async throws {
    let backdrop = BackdropView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    var issues: [String] = []
    backdrop.onIssue = { issues.append($0) }
    backdrop.scene = .desktop
    backdrop.wallpaper = Wallpaper(name: "Missing", url: URL(fileURLWithPath: "/nonexistent.heic"))
    try await waitUntil("the failed load") { backdrop.pendingImages == 0 && !issues.isEmpty }
    XCTAssertEqual(issues, ["Cannot read wallpaper Missing"])
  }

  @MainActor func testStageControlsChooseSceneThemeAndWallpaper() throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    let root = try XCTUnwrap(controller.window.contentView)
    let views = descendants(of: root)
    let scenes = try XCTUnwrap(
      views.compactMap { $0 as? NSSegmentedControl }.first {
        $0.label(forSegment: 0) == "Desktop"
      })
    XCTAssertEqual(
      (0..<scenes.segmentCount).map { scenes.label(forSegment: $0) },
      ["Desktop", "Article", "Code", "Photos"])
    let themes = try XCTUnwrap(
      views.compactMap { $0 as? NSSegmentedControl }.first {
        $0.label(forSegment: 0) == "Light" && $0.segmentCount == 2
      })
    let popup = try XCTUnwrap(views.compactMap { $0 as? NSPopUpButton }.first)
    XCTAssertEqual(popup.itemTitles, Wallpapers.installed().map(\.name))
    let backdrop = try XCTUnwrap(views.compactMap { $0 as? BackdropView }.first)

    themes.selectedSegment = 1
    XCTAssertTrue(themes.sendAction(themes.action, to: themes.target))
    XCTAssertEqual(backdrop.theme, .dark)
    XCTAssertEqual(backdrop.appearance?.name, .darkAqua)

    scenes.selectedSegment = 2
    XCTAssertTrue(scenes.sendAction(scenes.action, to: scenes.target))
    XCTAssertEqual(backdrop.scene, .code)
    XCTAssertFalse(popup.isEnabled, "The code editor shows no wallpaper")
    scenes.selectedSegment = 1
    XCTAssertTrue(scenes.sendAction(scenes.action, to: scenes.target))
    XCTAssertTrue(popup.isEnabled)

    let sonoma = try XCTUnwrap(popup.itemTitles.firstIndex(of: "Sonoma"))
    popup.selectItem(at: sonoma)
    XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
    XCTAssertEqual(backdrop.wallpaper?.name, "Sonoma")
  }
}
