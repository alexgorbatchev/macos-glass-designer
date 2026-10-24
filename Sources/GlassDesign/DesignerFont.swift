import AppKit
import CoreText

/// Process-local fonts travel with the app; no installation or system-font substitution.
@MainActor
enum DesignerFont {
  private static var resources: Bundle {
    if Bundle.main.bundleURL.pathExtension == "app" {
      guard
        let url = Bundle.main.url(
          forResource: "macos-glass-designer_GlassDesign", withExtension: "bundle"),
        let bundle = Bundle(url: url)
      else { preconditionFailure("The application is missing its font resources") }
      return bundle
    }
    return .module
  }
  private static let registered: Void = {
    for face in ["Regular", "Medium", "SemiBold"] {
      let name = "MapleMono-" + face
      guard let url = resources.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
      else {
        preconditionFailure("Missing bundled font: \(name)")
      }
      var error: Unmanaged<CFError>?
      let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
      if !success {
        let failure = error?.takeRetainedValue()
        // An installed copy can already own the PostScript name.
        guard NSFont(name: name, size: 12) != nil else {
          preconditionFailure("Cannot register \(name): \(String(describing: failure))")
        }
      }
    }
  }()

  static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    _ = registered
    let face = weight >= .semibold ? "SemiBold" : weight >= .medium ? "Medium" : "Regular"
    guard let font = NSFont(name: "MapleMono-" + face, size: size) else {
      preconditionFailure("Bundled Maple Mono face unavailable: \(face)")
    }
    return font
  }
}
