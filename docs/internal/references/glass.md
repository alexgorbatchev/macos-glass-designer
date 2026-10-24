---
created_on: 2026-10-23 12:00
last_modified: 2026-10-23 12:47
status: current
---

# Glass controls and evidence

This reference records the source contracts used by the designer. It is for agents extending the renderer or transferring a copied recipe into another native macOS project.

## Source projects

The sibling `simple-ptt/src/overlay/glass.rs` supplies evidence for progressive halo blur and masks. Its regular/clear halo styles are explicit renderer choices here, alongside progressive blur; there is no automatic fallback. `simple-ptt/src/overlay/private_effects.rs` supplies face color matrix and rim hooks. The designer starts with sparse override dictionaries empty.

`sol/macos/sol-macOS/managers/GlassLab.swift` and `sol/macos/sol-macOS/views/GlassLabWindow.swift` supply the material catalog, subvariants, private state controls, additional refraction/bleed/shadow inputs, fill placement, glass on/off, titled preview, and native keyboard-driven lists. The designer's generic presets are Regular, Clear, and Halo. The default is regular glass without tint or halo. Numeric slider ranges combine those projects' exploratory ranges; they are not documented Core Animation limits.

The native recipe, rather than a copied numerical snapshot, remains authoritative for missing overrides. On macOS 26.6.2 the native clear rim spread reads approximately 2.7475, while simple-ptt's optional override has a different tuned value. Copying native readouts into overrides automatically would change this contract.

## Native interfaces

The installed SDK's `AppKit.framework/Headers/NSGlassEffectView.h` exposes public style, corner radius, tint, content view, container spacing, and container content. Apple documents [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) and [container spacing](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview/spacing). The advanced controls have no public equivalent in that header.

Private hooks are isolated and checked at runtime:

- View KVC keys `_variant`, `_subvariant`, `_contentLensing`, `_subduedState`, `_scrimState`, `_adaptiveAppearance`, `_interactionState`, `_useReducedShadowRadius`.
- Filter paths `filters.glassBackground.<input>` on descendant layers. Sparse numeric overrides are reapplied after AppKit builds the material.
- `CASDFKeyFillHighlightEffect` key/fill amounts and spreads, plus curvature; reassign `layer.effect` after mutation.
- `CAFilter` type `variableBlur` on an `NSVisualEffectView` backdrop, with radius, mask image, normalized edges, and display scale. Embedded previews sample within the window; detached previews sample behind their transparent window.

[UIFoundation's macOS 26.6 private configuration research](https://github.com/Mx-Iris/UIFoundation/blob/main/Researchs/AppKit-NSGlassEffectView-PrivateConfiguration.md) corroborates the enum values. macOS 27 catalog additions are deliberately excluded. Availability does not guarantee identical appearance across macOS releases.

## Export semantics

Swift output contains every recipe field, exact floating-point literals, and platform/API mapping comments. It compiles independently, with no import of this project. It specifies values for an agent to implement; it does not claim to provide an executable renderer. JSON schema version 2 is the editable interchange format; version 1 is unsupported. The plain Swift clipboard representation carries JSON alongside it under `com.alexgorbatchev.glass-recipe`.

Halo mask X runs from outside edge to panel edge. The curve contains an ordered array of anchors, each with incoming and outgoing handles. Adjacent anchors define a cubic Bézier segment. Endpoint strengths are held outside their X positions; active X handles stay within their segment. Inserting a point on the curve splits its segment without changing its shape. When under-panel blur is disabled, each panel outline is cut out. Dimming follows the same mask, so raising the outer endpoint also raises outer-edge dimming. Shadows use a separate unclipped layer; they can coexist with the detached window's system shadow.

## Similar tools

The GitHub survey found these relevant projects:

- [LiquidGlassEffects / GlassLab](https://github.com/HoYeonPark1221/LiquidGlassEffects): the closest native material browser, with variants, subvariants, shapes, tint, backgrounds, and Swift export. Its catalog includes macOS 27 values. The inspected exporter hardcodes a blue tint and converts corner radius to an integer; this designer instead exports the chosen HSBA components and preserves fractional geometry.
- [qt-liquid-glass](https://github.com/fsalinas26/qt-liquid-glass): a Qt bridge to native glass, including a material lab and C++ snippets.
- [OpenNook](https://github.com/twinkling-reality/opennook): notch-focused glass playground with Swift/JSON sharing.
- [VisualEffectDebugger](https://github.com/insidegui/VisualEffectDebugger): inspection of older `NSVisualEffectView` materials.

This package uses system frameworks directly and does not depend on those tools.
