import AppKit
import GlassBridge

/// Runtime-checked macOS 26.6 glass controls.
/// SDK NSGlassEffectView.h exposes style/tint/corner/content only; no public replacements exist here.
@MainActor
enum PrivateGlass {
  static func read(_ object: AnyObject, _ key: String) -> Any? { GDRead(object, key, nil) }

  @discardableResult
  static func write(_ object: AnyObject, _ key: String, _ value: Any?, issues: inout [String])
    -> Bool
  {
    var failure: NSString?
    let result = GDWrite(object, key, value, &failure)
    if !result { issues.append(failure as String? ?? "Unavailable: \(key)") }
    return result
  }

  static func setView(_ view: NSView, _ key: String, _ value: Any?, issues: inout [String]) {
    guard view.responds(to: NSSelectorFromString("set\(key):")) else {
      issues.append("Unavailable view setter: set\(key):")
      return
    }
    write(view, key, value, issues: &issues)
  }

  static func layers(_ root: CALayer?) -> [CALayer] {
    guard let root else { return [] }
    return [root] + (root.sublayers ?? []).flatMap { layers($0) }
  }

  static func backgrounds(_ view: NSView) -> [CALayer] {
    layers(view.layer).filter { layer in
      (layer.filters as? [NSObject])?.contains { read($0, "name") as? String == "glassBackground" }
        == true
    }
  }

  static func highlights(_ view: NSView) -> [(CALayer, NSObject)] {
    guard let cls = NSClassFromString("CASDFKeyFillHighlightEffect") else { return [] }
    return layers(view.layer).compactMap { layer in
      // 'effect' exists only on internal effect layers; check before KVC.
      guard layer.responds(to: NSSelectorFromString("effect")),
        let effect = read(layer, "effect") as? NSObject, effect.isKind(of: cls)
      else { return nil }
      return (layer, effect)
    }
  }

  static func apply(_ p: GlassParameters, to glass: NSGlassEffectView, issues: inout [String]) {
    if p.variant == 1 { glass.style = .regular } else if p.variant == 2 { glass.style = .clear }
    // Preserve exact private value 0; it renders regular but is distinct from public .regular.
    if p.variant != 1 && p.variant != 2 { setView(glass, "_variant", p.variant, issues: &issues) }
    setView(glass, "_subvariant", p.subvariant, issues: &issues)
    for (key, value) in [
      ("_contentLensing", p.contentLensing), ("_subduedState", p.subduedState),
      ("_scrimState", p.scrimState), ("_adaptiveAppearance", p.adaptiveAppearance),
      ("_interactionState", p.interactionState),
    ] { setView(glass, key, value, issues: &issues) }
    setView(glass, "_useReducedShadowRadius", p.useReducedShadowRadius, issues: &issues)
    glass.cornerRadius = p.cornerRadius
    glass.tintColor =
      p.tintAlpha == 0
      ? nil
      : NSColor(
        calibratedHue: p.tintHue, saturation: p.tintSaturation, brightness: p.tintBrightness,
        alpha: p.tintAlpha)
  }

  static func installHalo(
    _ effect: NSVisualEffectView, radius: Double, mask: CGImage, scale: Double,
    issues: inout [String]
  ) -> Bool {
    guard
      let backdrop = layers(effect.layer).first(where: {
        NSStringFromClass(type(of: $0)) == "CABackdropLayer"
      })
    else {
      issues.append("Blur backdrop not available")
      return false
    }
    let existing =
      (backdrop.filters as? [NSObject])?.contains { read($0, "name") as? String == "variableBlur" }
      == true
    if existing {
      write(backdrop, "filters.variableBlur.inputRadius", radius, issues: &issues)
      write(backdrop, "filters.variableBlur.inputMaskImage", mask, issues: &issues)
    } else {
      guard let filter = GDMakeFilter("variableBlur") as? NSObject else {
        issues.append("Private variableBlur filter unavailable")
        return false
      }
      guard write(filter, "inputRadius", radius, issues: &issues),
        write(filter, "inputMaskImage", mask, issues: &issues),
        write(filter, "inputNormalizeEdges", true, issues: &issues)
      else { return false }
      backdrop.filters = [filter]
    }
    write(backdrop, "scale", scale, issues: &issues)
    backdrop.superlayer?.sublayers?.filter { $0 !== backdrop }.forEach { $0.isHidden = true }
    return true
  }
}
