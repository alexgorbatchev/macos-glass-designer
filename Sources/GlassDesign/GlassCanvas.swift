import AppKit

/// Actual AppKit glass, including container merging, a backdrop halo, and separate unclipped shadows.
@MainActor
public final class GlassCanvas: NSView {
  public private(set) var parameters = GlassParameters()
  public private(set) var nativeFilterInputs: [String: Double] = [:]
  public private(set) var nativeHighlightInputs: [String: Double] = [:]
  public private(set) var issues: [String] = []
  public var onReadout: (() -> Void)?
  public private(set) var secondaryVisible = false
  private(set) var container = NSGlassEffectContainerView()
  private let host = NSView()
  private var mainGlass = NSGlassEffectView()
  private var secondaryGlass = NSGlassEffectView()
  private let halo = NSVisualEffectView()
  private let haloGlassHost = NSView()
  private let haloGlass = NSGlassEffectView()
  private let plainMain = SampleContent(secondary: false)
  private let plainSecondary = SampleContent(secondary: true)
  private let haloDim = NSView()
  private let shadowView = NSView()
  private let fills = NSView()
  private var maskKey: String?
  private var mask: CGImage?
  var haloMaskImage: CGImage? { mask }
  private var syncScheduled = false
  private var paintScheduled = false
  private(set) var secondaryAnimating = false
  private var animationGeneration = 0
  private var configurationIssues: [String] = []
  private let nativeReadouts = NativeReadouts()
  var mainSurfaceFrame: CGRect { mainGlass.frame }
  var visibleSurfaceBounds: CGRect {
    secondaryGlass.isHidden ? mainGlass.frame : mainGlass.frame.union(secondaryGlass.frame)
  }
  var shadowBounds: CGRect? { shadowView.layer?.shadowPath?.boundingBoxOfPath }
  var activeHaloMode: Int? {
    if !halo.isHidden { return 0 }
    if !haloGlassHost.isHidden { return haloGlass.style == .regular ? 1 : 2 }
    return nil
  }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    halo.material = .hudWindow
    halo.blendingMode = .withinWindow
    halo.state = .active
    halo.wantsLayer = true
    for view in [haloDim, haloGlassHost, shadowView, fills, host] {
      view.wantsLayer = true
    }
    addSubview(halo)
    addSubview(haloGlassHost)
    haloGlassHost.addSubview(haloGlass)
    addSubview(haloDim)
    addSubview(shadowView)
    addSubview(fills)
    fills.addSubview(plainMain)
    fills.addSubview(plainSecondary)
    installGlass()
  }

  required init?(coder: NSCoder) { nil }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Behind-window sampling is required only by the detached transparent preview.
    halo.blendingMode = window?.isOpaque == false ? .behindWindow : .withinWindow
    needsLayout = true
    scheduleReadout()
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    scheduleReadout()
  }

  public func update(_ p: GlassParameters) throws {
    try p.validate()
    let old = parameters
    parameters = p
    configurationIssues = []
    let recipeChanged =
      old.glassEnabled != p.glassEnabled || old.variant != p.variant
      || old.subvariant != p.subvariant
      || old.appearance != p.appearance || old.contentLensing != p.contentLensing
      || old.subduedState != p.subduedState || old.scrimState != p.scrimState
      || old.adaptiveAppearance != p.adaptiveAppearance
      || old.interactionState != p.interactionState
      || old.useReducedShadowRadius != p.useReducedShadowRadius
      || !Set(old.filterInputs.keys).isSubset(of: Set(p.filterInputs.keys))
      || !Set(old.highlightInputs.keys).isSubset(of: Set(p.highlightInputs.keys))
    if recipeChanged || secondaryAnimating {
      rebuildGlass()
    } else {
      for glass in [mainGlass, secondaryGlass] {
        PrivateGlass.apply(p, to: glass, issues: &configurationIssues)
      }
    }
    appearance =
      p.appearance == 0 ? nil : NSAppearance(named: p.appearance == 1 ? .aqua : .darkAqua)
    container.spacing = p.mergeSpacing
    container.isHidden = !p.glassEnabled
    if window?.isOpaque == false { window?.hasShadow = p.windowShadow }
    if old.cornerRadius != p.cornerRadius {
      // The public setter leaves AppKit's hosted SDF geometry cached during slider tracking.
      // Invalidate the native subtree; do not override its generated layers.
      func invalidate(_ view: NSView) {
        view.needsLayout = true
        view.subviews.forEach(invalidate)
      }
      invalidate(container)
    }
    needsLayout = true
    layoutSubtreeIfNeeded()
    scheduleReadout()
  }

  private func rebuildGlass() {
    animationGeneration += 1
    secondaryAnimating = false
    NotificationCenter.default.removeObserver(
      self, name: NSView.frameDidChangeNotification, object: nil)
    // The container owns the combined glassBackground filter. Replacing only descendants
    // leaves overrides cached in that filter (native regression test on macOS 26.6.2).
    container.contentView = nil
    container.removeFromSuperview()
    mainGlass.removeFromSuperview()
    secondaryGlass.removeFromSuperview()
    container = NSGlassEffectContainerView()
    mainGlass = NSGlassEffectView()
    secondaryGlass = NSGlassEffectView()
    installGlass()
    nativeFilterInputs = [:]
    nativeHighlightInputs = [:]
  }

  /// Hosts the current container and glass views above the fills, configured for the recipe.
  private func installGlass() {
    container.wantsLayer = true
    container.spacing = parameters.mergeSpacing
    container.contentView = host
    addSubview(container)
    mainGlass.contentView = SampleContent(secondary: false)
    secondaryGlass.contentView = SampleContent(secondary: true)
    host.addSubview(mainGlass)
    host.addSubview(secondaryGlass)
    for glass in [mainGlass, secondaryGlass] {
      glass.postsFrameChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(surfaceFrameChanged(_:)),
        name: NSView.frameDidChangeNotification, object: glass)
      PrivateGlass.apply(parameters, to: glass, issues: &configurationIssues)
    }
  }

  /// The main surface centred in the canvas, before the preview offset. The centre sits on a
  /// device pixel and the origin is not rounded: rounding the origin of a centred rectangle moves
  /// its centre by up to half a point as its size changes, which makes centred content jiggle
  /// while a size slider moves.
  private var centredMainFrame: CGRect {
    let p = parameters
    let backing = convertToBacking(CGPoint(x: bounds.midX, y: bounds.midY))
    let centre = convertFromBacking(CGPoint(x: backing.x.rounded(), y: backing.y.rounded()))
    return CGRect(
      x: centre.x - p.width / 2, y: centre.y - p.height / 2, width: p.width,
      height: p.height + (secondaryVisible && p.secondaryEffect == 4 ? 80 + p.panelGap : 0))
  }

  var mainFrame: CGRect {
    let offset = clamped(surfaceOffset)
    return centredMainFrame.offsetBy(dx: offset.dx, dy: offset.dy)
  }

  // MARK: - Moving the embedded glass

  /// Whether dragging the glass moves it over the scene. The embedded stage sets this; the
  /// detached preview leaves it off so a drag moves its window instead.
  var movesSurfaces = false
  /// Where the glass sits relative to the centre. Preview-only: not part of the recipe.
  private var surfaceOffset = CGVector.zero
  private var dragStart: (point: CGPoint, offset: CGVector)?

  /// Keeps the glass, and the second surface above it, inside the canvas. A group larger than
  /// the canvas stays centred on that axis.
  private func clamped(_ offset: CGVector) -> CGVector {
    let main = centredMainFrame
    let group =
      secondaryVisible && parameters.secondaryEffect != 4
      ? main.union(
        CGRect(
          x: main.minX, y: main.maxY + parameters.panelGap, width: parameters.width, height: 80))
      : main
    func axis(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
      low > high ? 0 : min(high, max(low, value.rounded()))
    }
    return CGVector(
      dx: axis(offset.dx, bounds.minX - group.minX, bounds.maxX - group.maxX),
      dy: axis(offset.dy, bounds.minY - group.minY, bounds.maxY - group.maxY))
  }

  /// The embedded preview is a picture: its glass and sample text take no clicks of their own,
  /// so a press anywhere on it reaches the canvas.
  public override func hitTest(_ point: NSPoint) -> NSView? {
    guard movesSurfaces else { return super.hitTest(point) }
    return frame.contains(point) ? self : nil
  }

  public override func resetCursorRects() {
    if movesSurfaces { addCursorRect(visibleSurfaceBounds, cursor: .openHand) }
  }

  public override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard movesSurfaces, !secondaryAnimating, visibleSurfaceBounds.contains(point) else {
      super.mouseDown(with: event)
      return
    }
    dragStart = (point, surfaceOffset)
    NSCursor.closedHand.push()
  }

  public override func mouseDragged(with event: NSEvent) {
    guard let dragStart else {
      super.mouseDragged(with: event)
      return
    }
    let point = convert(event.locationInWindow, from: nil)
    surfaceOffset = clamped(
      CGVector(
        dx: dragStart.offset.dx + point.x - dragStart.point.x,
        dy: dragStart.offset.dy + point.y - dragStart.point.y))
    needsLayout = true
    layoutSubtreeIfNeeded()
  }

  public override func mouseUp(with event: NSEvent) {
    guard dragStart != nil else {
      super.mouseUp(with: event)
      return
    }
    dragStart = nil
    NSCursor.pop()
  }

  var secondaryFrame: CGRect {
    CGRect(
      x: mainFrame.minX, y: mainFrame.maxY + parameters.panelGap, width: parameters.width,
      height: 80)
  }

  public override func layout() {
    super.layout()
    container.frame = bounds
    host.frame = bounds
    if !secondaryAnimating {
      mainGlass.frame = mainFrame
      secondaryGlass.frame = secondaryFrame
    }
    mainGlass.contentView?.frame = mainGlass.bounds
    secondaryGlass.contentView?.frame = secondaryGlass.bounds
    if !secondaryAnimating {
      secondaryGlass.isHidden = !secondaryVisible || parameters.secondaryEffect == 4
    }
    for view in [shadowView, fills, halo, haloGlassHost, haloDim] { view.frame = bounds }
    if movesSurfaces { window?.invalidateCursorRects(for: self) }
    layoutPaint()
    scheduleReadout()
  }

  private func layoutPaint() {
    let p = parameters
    let panels = [mainGlass.frame] + (secondaryGlass.isHidden ? [] : [secondaryGlass.frame])
    plainMain.isHidden = p.glassEnabled
    plainSecondary.isHidden = p.glassEnabled || secondaryGlass.isHidden
    plainMain.frame = mainGlass.frame
    plainSecondary.frame = secondaryGlass.frame
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let path = CGMutablePath()
    for panel in panels {
      path.addRoundedRect(in: panel, cornerWidth: p.cornerRadius, cornerHeight: p.cornerRadius)
    }
    shadowView.layer?.shadowColor = NSColor.black.cgColor
    shadowView.layer?.shadowPath = path
    shadowView.layer?.shadowOpacity = p.customShadow ? Float(p.shadowOpacity) : 0
    shadowView.layer?.shadowRadius = p.shadowRadius
    shadowView.layer?.shadowOffset = CGSize(width: p.shadowOffsetX, height: p.shadowOffsetY)
    fills.layer?.sublayers?.filter { $0.name == "designer.fill" }.forEach {
      $0.removeFromSuperlayer()
    }
    for panel in panels {
      let dim = CALayer()
      dim.name = "designer.fill"
      dim.frame = panel
      dim.cornerRadius = p.cornerRadius
      dim.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(p.dim).cgColor
      fills.layer?.insertSublayer(dim, at: 0)
      if !p.fillInside {
        let fill = CALayer()
        fill.name = "designer.fill"
        fill.frame = panel
        fill.cornerRadius = p.cornerRadius
        fill.backgroundColor = fillColor.cgColor
        fills.layer?.insertSublayer(fill, above: dim)
      }
    }
    for content in [mainGlass.contentView, secondaryGlass.contentView, plainMain, plainSecondary]
      .compactMap({ $0 })
    {
      content.wantsLayer = true
      content.layer?.backgroundColor = p.fillInside ? fillColor.cgColor : nil
      content.layer?.cornerRadius = p.cornerRadius
      content.layer?.masksToBounds = true
    }
    halo.isHidden = !p.haloEnabled || p.haloMode != 0
    haloGlassHost.isHidden = !p.haloEnabled || p.haloMode == 0
    haloGlass.style = p.haloMode == 1 ? .regular : .clear
    haloGlass.cornerRadius = p.cornerRadius + p.haloMargin
    haloGlass.frame = panels.dropFirst().reduce(panels[0]) { $0.union($1) }.insetBy(
      dx: -p.haloMargin, dy: -p.haloMargin)
    haloDim.isHidden = !p.haloEnabled
    if p.haloEnabled {
      let scale = window?.backingScaleFactor ?? 2
      let key =
        "\(bounds.size):\(panels):\(p.haloMargin):\(p.cornerRadius):\(p.haloUnderPanels):\(scale):"
        + String(describing: p.haloCurve)
      if maskKey != key {
        mask = HaloMask.make(size: bounds.size, panels: panels, p: p, scale: scale)
        maskKey = key
      }
      let dimMask = CALayer()
      dimMask.frame = bounds
      dimMask.contents = mask
      dimMask.contentsScale = scale
      haloDim.layer?.backgroundColor = NSColor.black.withAlphaComponent(p.haloDim).cgColor
      haloDim.layer?.mask = dimMask
      let glassMask = CALayer()
      glassMask.frame = bounds
      glassMask.contents = mask
      glassMask.contentsScale = scale
      haloGlassHost.layer?.mask = glassMask
    }
    CATransaction.commit()
  }

  private var fillColor: NSColor {
    NSColor(
      hue: parameters.fillHue, saturation: parameters.fillSaturation,
      brightness: parameters.fillBrightness, alpha: parameters.fillAlpha)
  }

  @objc private func surfaceFrameChanged(_ notification: Notification) {
    guard secondaryAnimating, !paintScheduled else { return }
    paintScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.paintScheduled = false
      self.mainGlass.contentView?.frame = self.mainGlass.bounds
      self.secondaryGlass.contentView?.frame = self.secondaryGlass.bounds
      self.layoutPaint()
      self.refreshInternals()
    }
  }

  private func scheduleReadout() {
    guard !syncScheduled, window != nil else { return }
    syncScheduled = true
    // Default-mode dispatch waits until a slider is released. Native tracking uses common modes.
    RunLoop.main.perform(inModes: [.common]) { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.syncScheduled = false
        self.container.layoutSubtreeIfNeeded()
        // NSVisualEffectView builds its backdrop during display, including after window-style changes.
        self.halo.needsDisplay = true
        self.halo.displayIfNeeded()
        self.window?.displayIfNeeded()
        self.refreshInternals()
      }
    }
  }

  public func refreshInternals() {
    var issues = configurationIssues
    let backgrounds =
      parameters.glassEnabled ? PrivateGlass.backgrounds(container, issues: &issues) : []
    nativeFilterInputs = [:]
    nativeHighlightInputs = [:]
    if backgrounds.isEmpty && parameters.glassEnabled {
      issues.append("AppKit has not exposed a glassBackground layer for this recipe")
    }
    for (index, background) in backgrounds.enumerated() {
      let natives = nativeReadouts.natives(of: background, keys: GlassCatalog.filters.map(\.key)) {
        key in
        (PrivateGlass.read(background, "filters.glassBackground.\(key)", issues: &issues)
          as? NSNumber)?.doubleValue
      }
      if index == 0 { nativeFilterInputs = natives }
      for (key, value) in parameters.filterInputs {
        PrivateGlass.write(background, "filters.glassBackground.\(key)", value, issues: &issues)
      }
      nativeReadouts.recordWrites(parameters.filterInputs, to: background)
    }
    let highlights =
      parameters.glassEnabled ? PrivateGlass.highlights(container, issues: &issues) : []
    for (index, (layer, effect)) in highlights.enumerated() {
      let natives = nativeReadouts.natives(of: effect, keys: GlassCatalog.highlights.map(\.key)) {
        key in (PrivateGlass.read(effect, key, issues: &issues) as? NSNumber)?.doubleValue
      }
      if index == 0 { nativeHighlightInputs = natives }
      for (key, value) in parameters.highlightInputs {
        PrivateGlass.write(effect, key, value, issues: &issues)
      }
      nativeReadouts.recordWrites(parameters.highlightInputs, to: effect)
      if !parameters.highlightInputs.isEmpty {
        PrivateGlass.write(layer, "effect", effect, issues: &issues)
      }
    }
    if parameters.glassEnabled && !parameters.highlightInputs.isEmpty && highlights.isEmpty {
      issues.append("Rim highlight effect unavailable for this recipe")
    }
    if parameters.haloEnabled && parameters.haloMode == 0 {
      if let mask {
        if !PrivateGlass.installHalo(
          halo, radius: parameters.haloBlurRadius, mask: mask,
          scale: Double(window?.backingScaleFactor ?? 2), issues: &issues)
        {
          halo.isHidden = true
        }
      } else {
        issues.append("Unable to allocate blur mask")
      }
    }
    self.issues = Array(Set(issues)).sorted()
    onReadout?()
  }

  public func pop() {
    guard let layer else { return }
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let scale = CAKeyframeAnimation(keyPath: "transform")
    let initial = reduced ? 1 : 1 - parameters.popShrink
    func transform(_ scale: Double) -> CATransform3D {
      var t = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
      t = CATransform3DScale(t, scale, scale, 1)
      return CATransform3DTranslate(t, -bounds.midX, -bounds.midY, 0)
    }
    scale.values = [
      NSValue(caTransform3D: transform(initial)),
      NSValue(caTransform3D: transform(reduced ? 1 : 1.1)),
      NSValue(caTransform3D: CATransform3DIdentity),
    ]
    scale.keyTimes = [0, 0.65, 1]
    scale.duration = parameters.popSeconds
    layer.add(scale, forKey: "designer.pop")
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = reduced ? 0 : parameters.popOpacity
    fade.toValue = 1
    fade.duration = parameters.popSeconds
    layer.add(fade, forKey: "designer.fade")
  }

  public func toggleSecondary() {
    guard !secondaryAnimating else { return }
    let p = parameters
    let appearing = !secondaryVisible
    let restingMain = mainFrame
    let restingSecondary = secondaryFrame
    secondaryVisible = appearing
    let targetMain = mainFrame
    let targetSecondary = secondaryFrame
    let main = mainGlass
    let secondary = secondaryGlass
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      needsLayout = true
      layoutSubtreeIfNeeded()
      return
    }
    secondaryAnimating = true
    let generation = animationGeneration
    let start = Self.secondaryStart(
      frame: appearing ? targetSecondary : restingSecondary, main: restingMain, p: p)
    secondary.isHidden = p.secondaryEffect == 4
    if appearing && p.secondaryEffect != 4 { secondary.frame = start }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = p.secondarySeconds
      context.timingFunction =
        p.secondaryEasing == 1 && appearing
        ? CAMediaTimingFunction(controlPoints: 0.34, 1.36, 0.64, 1)
        : CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
      if p.secondaryEffect == 4 || targetMain != restingMain {
        main.animator().frame = targetMain
      }
      if p.secondaryEffect != 4 {
        secondary.animator().frame = appearing ? targetSecondary : start
      }
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.animationGeneration == generation else { return }
        self.secondaryAnimating = false
        self.needsLayout = true
        self.layoutSubtreeIfNeeded()
      }
    }
  }

  static func secondaryStart(frame: CGRect, main: CGRect, p: GlassParameters) -> CGRect {
    switch p.secondaryEffect {
    case 0:
      return CGRect(
        x: frame.midX - frame.width * 0.15, y: main.maxY - 10, width: frame.width * 0.3, height: 20)
    case 1: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 1)
    case 2:
      return frame.insetBy(dx: frame.width * p.popShrink / 2, dy: frame.height * p.popShrink / 2)
    case 3: return frame.offsetBy(dx: 0, dy: -frame.height - p.panelGap)
    default: return frame
    }
  }
}

@MainActor
private final class SampleContent: NSView {
  init(secondary: Bool) {
    super.init(frame: .zero)
    let title = NSTextField(labelWithString: secondary ? "A second surface" : "Made of light.")
    title.font = DesignerFont.font(size: secondary ? 15 : 28, weight: .semibold)
    title.alignment = .center
    let subtitle = NSTextField(
      wrappingLabelWithString: secondary
        ? "Watch the edges merge as this panel moves."
        : "Glass, refraction, and a little atmosphere.\nTune the material. Keep the recipe.")
    subtitle.font = DesignerFont.font(size: 12)
    subtitle.textColor = .secondaryLabelColor
    subtitle.alignment = .center
    let stack = NSStackView(views: [title, subtitle])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      title.widthAnchor.constraint(equalTo: stack.widthAnchor),
      subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }
  required init?(coder: NSCoder) { nil }
}
