import AppKit

enum BackdropScene: Int, CaseIterable {
  case desktop, article, code, photos

  var title: String {
    switch self {
    case .desktop: "Desktop"
    case .article: "Article"
    case .code: "Code"
    case .photos: "Photos"
    }
  }

  var showsWallpaper: Bool { self == .desktop || self == .article }
}

enum BackdropTheme: Int, CaseIterable {
  case light, dark

  var title: String { self == .light ? "Light" : "Dark" }
  var appearance: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
}

/// The screen behind the embedded glass: a drawn app scene in a light or dark theme.
/// Scenes resolve AppKit's semantic colors under the theme's appearance, so they use the system's
/// real light and dark palettes; wallpapers and photos come from the wallpapers installed on this Mac.
@MainActor
final class BackdropView: NSView {
  var scene = BackdropScene.desktop {
    didSet { reload() }
  }
  var theme = BackdropTheme.light {
    didSet {
      appearance = NSAppearance(named: theme.appearance)
      reload()
    }
  }
  var wallpaper: Wallpaper? {
    didSet { reload() }
  }
  var onIssue: ((String) -> Void)?
  /// Image decodes still running; scenes draw without them until they finish.
  private(set) var pendingImages = 0

  private struct ImageKey: Hashable {
    let url: URL
    let dark: Bool
    let maxPixelSize: Int
  }
  private static let wallpaperPixels = 2048
  private static let photoPixels = 480
  /// Installed wallpapers, scanned once; the photo scene shows all of them.
  let installedWallpapers: [Wallpaper]
  private var images: [ImageKey: CGImage] = [:]
  private var loading: Set<ImageKey> = []
  private var failed: Set<ImageKey> = []

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    installedWallpapers = Wallpapers.installed()
    super.init(frame: frameRect)
    appearance = NSAppearance(named: theme.appearance)
    reload()
  }

  required init?(coder: NSCoder) { nil }

  override func draw(_ dirtyRect: NSRect) {
    SceneRenderer(
      bounds: bounds, wallpaper: wallpaperKey.flatMap { images[$0] },
      photos: photoKeys.compactMap { images[$0] }, dark: theme == .dark
    ).draw(scene)
  }

  private var wallpaperKey: ImageKey? {
    guard scene.showsWallpaper, let wallpaper else { return nil }
    return ImageKey(url: wallpaper.url, dark: theme == .dark, maxPixelSize: Self.wallpaperPixels)
  }

  /// Photos are photos: they look the same in both themes.
  private var photoKeys: [ImageKey] {
    guard scene == .photos else { return [] }
    return installedWallpapers.map {
      ImageKey(url: $0.url, dark: false, maxPixelSize: Self.photoPixels)
    }
  }

  private var neededKeys: Set<ImageKey> { Set([wallpaperKey].compactMap { $0 } + photoKeys) }

  private func reload() {
    needsDisplay = true
    let needed = neededKeys
    // Full-size wallpapers are large; keep only the one on screen.
    images = images.filter { $0.key.maxPixelSize == Self.photoPixels || needed.contains($0.key) }
    if scene == .photos && installedWallpapers.isEmpty {
      onIssue?("No installed wallpapers to show as photos")
    }
    for key in needed where images[key] == nil && !loading.contains(key) && !failed.contains(key) {
      load(key)
    }
  }

  private func load(_ key: ImageKey) {
    let source =
      [wallpaper].compactMap { $0 }.first { $0.url == key.url }
      ?? installedWallpapers.first { $0.url == key.url }
    guard let source else { return }
    loading.insert(key)
    pendingImages += 1
    Task {
      // Wallpapers are up to 6016 pixels square; decode and downsample away from the main thread.
      let image = await Task.detached(priority: .userInitiated) {
        Wallpapers.decode(source, dark: key.dark, maxPixelSize: key.maxPixelSize)
      }.value
      loading.remove(key)
      pendingImages -= 1
      if let image {
        // A decode can finish after the scene, theme, or wallpaper moved on.
        guard neededKeys.contains(key) || key.maxPixelSize == Self.photoPixels else { return }
        images[key] = image
        needsDisplay = true
      } else {
        failed.insert(key)
        onIssue?("Cannot read wallpaper \(source.name)")
      }
    }
  }
}
