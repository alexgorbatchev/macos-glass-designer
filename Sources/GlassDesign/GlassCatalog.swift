import Foundation

public struct NumericField: @unchecked Sendable {
  public let title: String
  public let key: String
  public let path: WritableKeyPath<GlassParameters, Double>
  public let range: ClosedRange<Double>
  public let unit: String
  public let help: String

  init(
    _ title: String, _ key: String, _ path: WritableKeyPath<GlassParameters, Double>,
    _ range: ClosedRange<Double>, _ unit: String = "", help: String
  ) {
    self.title = title
    self.key = key
    self.path = path
    self.range = range
    self.unit = unit
    self.help = help
  }
}

public struct FilterField: Sendable {
  public let key: String
  public let range: ClosedRange<Double>
  public let help: String
  init(_ key: String, _ range: ClosedRange<Double>, _ help: String) {
    self.key = key
    self.range = range
    self.help = help
  }
}

/// Private values verified on macOS 26.6; never mix in macOS 27-only cases.
public enum GlassCatalog {
  public static let variants = [
    "default", "regular", "clear", "dock", "appIcons", "widgets", "text", "avplayer",
    "facetime", "controlCenter", "notificationCenter", "monogram", "bubbles", "identity",
    "focusBorder", "keyboard", "sidebar", "abuttedSidebar", "inspector", "loupe",
    "cartouchePopover",
  ]
  public static let subvariants = [
    "lockscreenControls", "lockscreenNotifications", "homescreenClose", "camera", "posterSwitcher",
    "homescreenResizeHandle", "cursorAccessory", "homescreenFolder", "tab", "focusedButtonFill",
    "entryField", "volumeSlider", "customizeSheet", "watchFacePhotos", "watchFacePhotosMini",
    "watchFaceFlowStencil", "watchFaceFlowSolid", "watchPasscode", "homescreenAppLibraryPod",
    "menu",
    "watchSmartStack", "watchSmartStackAnimatedContent", "siriSnippet", "alarmSlider", "mapsSign",
    "sheet", "messagesTapback", "cluster", "secondaryCluster", "watchDetuned", "tvPortraitClock",
    "track", "iOSNotificationCenter",
  ]

  public static let surface: [NumericField] = [
    .init(
      "Corner radius", "cornerRadius", \.cornerRadius, 0...100, "pt",
      help: "Curvature of the glass corners, in points."),
    .init(
      "Width", "width", \.width, 180...800, "pt", help: "Width of each glass surface, in points."),
    .init(
      "Height", "height", \.height, 100...500, "pt",
      help: "Resting height of the main surface, in points."),
    .init(
      "Merge distance", "mergeSpacing", \.mergeSpacing, 0...80, "pt",
      help: "Distance at which neighboring surfaces merge, in points."),
    .init(
      "Panel gap", "panelGap", \.panelGap, 0...80, "pt",
      help: "Space between the main and second surfaces, in points."),
    .init(
      "Backing dim", "dim", \.dim, 0...1,
      help: "Opacity of the system-colored backing beneath the glass."),
    .init(
      "Tint hue", "tintHue", \.tintHue, 0...1,
      help: "Glass tint color's position on the color wheel."),
    .init(
      "Tint saturation", "tintSaturation", \.tintSaturation, 0...1,
      help: "Color intensity of the glass tint."),
    .init(
      "Tint brightness", "tintBrightness", \.tintBrightness, 0...1,
      help: "Brightness of the glass tint."),
    .init(
      "Tint opacity", "tintAlpha", \.tintAlpha, 0...1,
      help: "Zero leaves the native material untinted."),
    .init(
      "Fill hue", "fillHue", \.fillHue, 0...1,
      help: "Backing fill color's position on the color wheel."),
    .init(
      "Fill saturation", "fillSaturation", \.fillSaturation, 0...1,
      help: "Color intensity of the backing fill."),
    .init(
      "Fill brightness", "fillBrightness", \.fillBrightness, 0...1,
      help: "Brightness of the backing fill."),
    .init(
      "Fill opacity", "fillAlpha", \.fillAlpha, 0...1,
      help: "Opacity of the fill placed inside or beneath the glass."),
  ]
  public static let shadow: [NumericField] = [
    .init(
      "Opacity", "shadowOpacity", \.shadowOpacity, 0...1,
      help: "Strength of the custom black shadow."),
    .init(
      "Blur radius", "shadowRadius", \.shadowRadius, 0...80, "pt",
      help: "Softness of the custom shadow, in points."),
    .init(
      "Horizontal offset", "shadowOffsetX", \.shadowOffsetX, -60...60, "pt",
      help: "Positive values move the shadow right, in points."),
    .init(
      "Vertical offset", "shadowOffsetY", \.shadowOffsetY, -60...60, "pt",
      help: "Positive values move the shadow up, in points."),
  ]
  public static let halo: [NumericField] = [
    .init(
      "Margin", "haloMargin", \.haloMargin, 0...160, "pt",
      help: "How far the blur extends beyond the surface, in points."),
    .init(
      "Blur radius", "haloBlurRadius", \.haloBlurRadius, 0...80, "pt",
      help: "Backdrop blur radius at full curve strength, in points."),
    .init(
      "Dimming", "haloDim", \.haloDim, 0...0.9,
      help: "Black dimming through the same strength curve as the blur."),
  ]
  public static let motion: [NumericField] = [
    .init(
      "Pop duration", "popSeconds", \.popSeconds, 0...1.5, "s",
      help: "Time for the pop preview to finish, in seconds."),
    .init(
      "Pop shrink", "popShrink", \.popShrink, 0...0.5,
      help: "Starting shrink as a fraction of the surface size."),
    .init(
      "Pop edge opacity", "popOpacity", \.popOpacity, 0...1,
      help: "Starting opacity of the pop preview."),
    .init(
      "Second duration", "secondarySeconds", \.secondarySeconds, 0.05...1.5, "s",
      help: "Time to show or hide the second surface, in seconds."),
  ]
  public static let filters: [FilterField] = [
    .init(
      "inputInnerRefractionAmount", -400...300, "Inner-edge bending; negative values bend inward."),
    .init("inputInnerRefractionHeight", 0...120, "Inner refraction reach, in points."),
    .init("inputOuterRefractionAmount", -200...200, "Bending at the outermost rim."),
    .init("inputOuterRefractionHeight", 0...120, "Outer refraction band, in points."),
    .init("inputRefractionOpacity", 0...1, "Refraction layer opacity."),
    .init("inputBlurRadius", 0...60, "Backdrop frost radius, in points."),
    .init("inputBleedAmount", 0...200, "Edge color bleed strength."),
    .init("inputBleedHeight", 0...120, "Color bleed reach, in points."),
    .init("inputBleedBlurRadius", 0...60, "Color bleed blur radius, in points."),
    .init("inputBleedOpacity", 0...1, "Color bleed opacity."),
    .init("inputShadowOpacity", 0...1, "Glass's inner shadow opacity."),
    .init("inputShadowAmount", 0...200, "Inner shadow strength."),
    .init("inputShadowHeight", 0...120, "Inner shadow reach, in points."),
    .init("inputShadowBlurRadius", 0...60, "Inner shadow softness, in points."),
    .init("inputFaceOpacity", 0...1, "Flat face layer opacity."),
    .init("inputFaceColorMatrixWhite", 0...1.5, "Face color matrix white multiplier."),
    .init("inputFaceColorMatrixBlack", 0...1, "Face color matrix black offset."),
    .init("inputFaceColorMatrixSaturation", 0...3, "Face saturation multiplier."),
    .init("inputSDRShadowOpacity", 0...1, "Standard dynamic range edge shading."),
  ]
  public static let highlights: [FilterField] = [
    .init("keyAmount", 0...2, "Rim key light strength."),
    .init("fillAmount", 0...2, "Rim fill light strength."),
    .init("keySpread", 0...6, "Rim key light spread."),
    .init("fillSpread", 0...6, "Rim fill light spread."),
    .init("curvature", 0...2, "Rim highlight curvature."),
  ]
  public static let allNumbers = surface + shadow + halo + motion
}
