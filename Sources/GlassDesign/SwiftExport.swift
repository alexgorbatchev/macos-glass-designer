import Foundation

public enum SwiftExport {
  /// Standalone Swift value specification, deliberately independent of this app or any package.
  public static func source(for parameters: GlassParameters, observed: [String: Double]) throws
    -> String
  {
    try parameters.validate()
    var lines = [
      "// macOS Glass Designer — \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "// Swift parameter specification for agents using AppKit, objc2, Qt, or another macOS bridge.",
      "// All distances are points (not pixels). Durations are seconds. HSBA / opacity use 0...1.",
      "// Render with native NSGlassEffectView inside NSGlassEffectContainerView; minimum macOS 26.",
      "// Public: cornerRadius -> glass.cornerRadius; tint HSBA -> glass.tintColor (nil at alpha 0).",
      "// variant 1 -> .regular, 2 -> .clear; other variants require private set_variant:.",
      "// Private view keys: _variant, _subvariant, _contentLensing, _subduedState, _scrimState,",
      "// _adaptiveAppearance, _interactionState, _useReducedShadowRadius. Check setters at runtime.",
      "// appearance: 0 system, 1 Aqua, 2 DarkAqua. Lensing/adaptation: 0 automatic, 1 off, 2 on.",
      "// subdued/scrim: 0 automatic, 1 forced. Interaction: 0 idle, 1 pressed, 2 rollover.",
      "// mergeSpacing -> container.spacing; panelGap is the actual gap between two glass surfaces.",
      "// filterInputs: sparse overrides on CALayer key paths filters.glassBackground.<key>.",
      "// Apply after AppKit builds its layers, and reapply when the recipe/appearance rebuilds them.",
      "// highlightInputs: CASDFKeyFillHighlightEffect keys. Reassign layer.effect to redraw.",
      "// Missing dictionary keys mean AppKit default; observed values below are readouts, not overrides.",
      "// customShadow -> separate unclipped CALayer shadowPath, black; windowShadow -> NSWindow.hasShadow.",
      "// glassEnabled removes the glass material while keeping sample content and fills visible.",
      "// windowTitled chooses titled/closable vs borderless for the detached transparent NSWindow.",
      "// fillInside chooses a rounded fill in contentView; otherwise place fill/dim under the glass.",
      "// halo: NSVisualEffectView backdrop with private variableBlur, inputRadius / inputMaskImage;",
      "// set backdrop.scale to screen scale. Mask X: outside edge 0 -> panel edge 1; Y: blur strength.",
      "// haloCurve is an ordered array of cubic Bezier nodes, with position/incoming/outgoing handles.",
      "// Between nodes A/B use A.position, A.outgoing, B.incoming, B.position; solve X to evaluate Y.",
      "// Coordinates use 0...1. X runs outside-to-panel; Y is strength. Hold endpoint strengths beyond their X.",
      "// haloUnderPanels keeps full endpoint strength inside the surface; haloDim uses the same mask.",
      "// haloMode: 0 variableBlur backdrop, 1 masked regular NSGlassEffectView, 2 masked clear glass.",
      "// Masked-glass halo uses the expanded group outline, cornerRadius + haloMargin, and the same mask.",
      "// Pop scales the entire rendering root about its center and fades from popOpacity to 1.",
      "// secondaryEffect: 0 Emerge, 1 Unfold, 2 Pop, 3 Slide, 4 Expand (grow main surface upward).",
      "// The secondary sample is 80 points tall; Expand grows the main surface by 80 + panelGap.",
      "// secondaryEasing: 0 smooth [0.42,0,0.58,1], 1 spring-in [0.34,1.36,0.64,1].",
      "// Respect Reduce Motion: use an unscaled fade / immediate secondary placement.",
      "// Private APIs are OS-dependent. Report unavailable controls; do not substitute another material.",
      "", "struct GlassCurvePoint { var x: Double; var y: Double }",
      "struct GlassCurveNode {",
      "    var position: GlassCurvePoint",
      "    var incoming: GlassCurvePoint",
      "    var outgoing: GlassCurvePoint",
      "}", "", "struct DesignedGlassParameters {",
    ]
    for child in Mirror(reflecting: parameters).children {
      guard let key = child.label else { continue }
      let (type, value) = try literal(child.value)
      lines.append("    var \(key): \(type) = \(value)")
    }
    lines += ["}", "", "let glassParameters = DesignedGlassParameters()", ""]
    lines.append(
      "// Variant: \(parameters.variant) \(GlassCatalog.variants[parameters.variant]); subvariant: \(parameters.subvariant ?? "none")"
    )
    for field in GlassCatalog.filters where observed[field.key] != nil {
      lines.append("// Observed glassBackground.\(field.key) = \(observed[field.key]!)")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func literal(_ value: Any) throws -> (String, String) {
    switch value {
    case let value as Bool: return ("Bool", value ? "true" : "false")
    case let value as Int: return ("Int", String(value))
    case let value as Double: return ("Double", String(value))
    case let value as String: return ("String?", String(reflecting: value))
    case let value as [String: Double]:
      let entries = value.sorted { $0.key < $1.key }.map {
        "\(String(reflecting: $0.key)): \($0.value)"
      }
      return (
        "[String: Double]", entries.isEmpty ? "[:]" : "[" + entries.joined(separator: ", ") + "]"
      )
    case let value as HaloCurve:
      func point(_ p: CurvePoint) -> String { ".init(x: \(p.x), y: \(p.y))" }
      let nodes = value.nodes.map {
        "        .init(position: \(point($0.position)), incoming: \(point($0.incoming)), outgoing: \(point($0.outgoing)))"
      }
      return ("[GlassCurveNode]", "[\n" + nodes.joined(separator: ",\n") + "\n    ]")
    default:
      // The model's only optional field is subvariant. Mirror unwraps Optional.none here.
      let mirror = Mirror(reflecting: value)
      if mirror.displayStyle == .optional && mirror.children.isEmpty { return ("String?", "nil") }
      throw RecipeError.invalid("Unexportable parameter type: \(type(of: value))")
    }
  }
}
