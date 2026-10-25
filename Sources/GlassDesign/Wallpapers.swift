import AppKit
import ImageIO

public struct Wallpaper: Equatable, Sendable {
  public let name: String
  public let url: URL
  public init(name: String, url: URL) {
    self.name = name
    self.url = url
  }
}

/// Wallpapers installed on this Mac. Nothing is bundled: images are read from the system at runtime.
enum Wallpapers {
  private static let directories = [
    URL(fileURLWithPath: "/System/Library/Desktop Pictures"),
    URL(fileURLWithPath: "/Library/Desktop Pictures"),
  ]

  /// The current desktop picture first, then the full-size images in the system folders.
  /// Download-on-demand wallpapers (`.madesktop`) and the flat "Solid Colors" are skipped.
  @MainActor static func installed() -> [Wallpaper] {
    var urls: [URL] = []
    if let screen = NSScreen.main, let current = NSWorkspace.shared.desktopImageURL(for: screen) {
      urls.append(current)
    }
    for directory in directories {
      let contents =
        (try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
      urls += contents.filter {
        ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased())
      }
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
    }
    var seen = Set<URL>()
    return urls.map(\.standardizedFileURL).filter { seen.insert($0).inserted && isImage($0) }.map {
      Wallpaper(name: $0.deletingPathExtension().lastPathComponent, url: $0)
    }
  }

  private static func isImage(_ url: URL) -> Bool {
    CGImageSourceCreateWithURL(url as CFURL, nil).map { CGImageSourceGetCount($0) > 0 } ?? false
  }

  /// Decodes the variant for the theme, downsampled so the longest side is `maxPixelSize`.
  /// Dynamic wallpapers list their light and dark images in `apple_desktop:apr` metadata;
  /// other wallpapers show the same image in both themes, as on the desktop.
  nonisolated static func decode(_ wallpaper: Wallpaper, dark: Bool, maxPixelSize: Int)
    -> CGImage?
  {
    guard let source = CGImageSourceCreateWithURL(wallpaper.url as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else { return nil }
    let index = appearanceIndex(source, dark: dark) ?? 0
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
  }

  private nonisolated static func appearanceIndex(_ source: CGImageSource, dark: Bool) -> Int? {
    guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
      let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "apple_desktop:apr" as CFString),
      let encoded = CGImageMetadataTagCopyValue(tag) as? String,
      let data = Data(base64Encoded: encoded),
      let appearances = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let index = appearances[dark ? "d" : "l"] as? Int,
      index < CGImageSourceGetCount(source)
    else { return nil }
    return index
  }
}
