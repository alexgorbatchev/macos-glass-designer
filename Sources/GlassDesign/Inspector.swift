import AppKit

@MainActor
final class Inspector: NSView, NSTextFieldDelegate {
  private let tabs = NSSegmentedControl(
    labels: ["Surface", "Blur", "Shadow", "Filter", "Rim", "Motion"],
    trackingMode: .selectOne, target: nil, action: nil)
  private let scroll = NSScrollView()
  private let tabActions = ActionBindings()
  /// Targets of the current section; replaced whenever another inspector is shown.
  private let sectionActions = ActionBindings()
  private var syncs: [(GlassParameters, GlassCanvas) -> Void] = []
  private var current = GlassParameters()
  var onChange: (((inout GlassParameters) -> Void) -> Void)?
  var onSecondary: (() -> Void)?
  var onPop: (() -> Void)?
  private let document = FlippedView()
  private var form = NSStackView()
  private var lastCanvas: GlassCanvas?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    tabs.selectedSegment = 0
    tabs.segmentDistribution = .fillEqually
    tabs.controlSize = .small
    tabs.font = DesignerFont.font(size: 10)
    tabActions.bind(tabs) { [weak self] _ in self?.buildSection() }
    scroll.documentView = document
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let header = NSStackView(views: [
      label("INSPECTOR", size: 10, weight: .semibold, secondary: true), NSView(),
      label("⌘1–6", size: 10, secondary: true),
    ])
    header.distribution = .fill
    header.alignment = .centerY
    let stack = vertical([
      header, tabs, scroll,
    ])
    pin(stack, to: self)
    header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    tabs.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    document.translatesAutoresizingMaskIntoConstraints = false
    document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    buildSection()
  }
  required init?(coder: NSCoder) { nil }

  func selectTab(_ index: Int) {
    tabs.selectedSegment = index
    buildSection()
  }

  func sync(_ parameters: GlassParameters, canvas: GlassCanvas) {
    current = parameters
    lastCanvas = canvas
    syncs.forEach { $0(parameters, canvas) }
  }

  private func buildSection() {
    sectionActions.removeAll()
    syncs = []
    form.removeFromSuperview()
    form = vertical([], spacing: 13)
    pin(form, to: document, inset: 2)
    switch tabs.selectedSegment {
    case 0:
      heading(
        "Surface & color", "Dimensions in points. A zero tint opacity leaves the glass untinted.")
      toggle("Enable glass material", \.glassEnabled)
      toggle("Titled desktop preview", \.windowTitled)
      choice("Appearance", options: ["System", "Light", "Dark"], path: \.appearance)
      for field in GlassCatalog.surface {
        number(field, requiresSecondary: field.path == \.mergeSpacing || field.path == \.panelGap)
      }
      toggle("Place fill inside glass", \.fillInside)
      divider()
      heading(
        "System recipe states",
        "Private AppKit settings. 0/1 lensing are equivalent on macOS 26.6; 2 requests lensing.")
      choice("Content lensing", options: ["Auto", "Off", "On"], path: \.contentLensing)
      choice("Subdued", options: ["Auto", "Forced"], path: \.subduedState)
      choice("Scrim", options: ["Auto", "Forced"], path: \.scrimState)
      choice("Adaptive appearance", options: ["Auto", "Off", "On"], path: \.adaptiveAppearance)
      choice("Interaction", options: ["Idle", "Pressed", "Rollover"], path: \.interactionState)
    case 1:
      heading(
        "Progressive blur",
        "A masked backdrop blur around the glass. The curve runs from the outer edge (X=0) to the panel (X=1)."
      )
      toggle("Enable blur", \.haloEnabled)
      let curve = CurveEditor()
      curve.heightAnchor.constraint(equalToConstant: 320).isActive = true
      curve.onChange = { [weak self] value in self?.onChange? { $0.haloCurve = value } }
      add(curve)
      syncs.append { p, _ in
        curve.curve = p.haloCurve
      }
      let addPoint = actionButton("Add point", target: nil, action: nil)
      sectionActions.bind(addPoint) { _ in curve.addPoint() }
      let deletePoint = actionButton("Delete point", target: nil, action: nil)
      sectionActions.bind(deletePoint) { _ in curve.deleteSelectedPoint() }
      // Commits immediately, like the other segmented choices.
      let kinds = NSSegmentedControl(
        labels: CurvePointKind.allCases.map(\.title), trackingMode: .selectOne, target: nil,
        action: nil)
      kinds.controlSize = .small
      kinds.font = DesignerFont.font(size: 10)
      kinds.setAccessibilityLabel("Point type")
      sectionActions.bind(kinds) { sender in
        let index = (sender as! NSSegmentedControl).selectedSegment
        guard CurvePointKind.allCases.indices.contains(index) else { return }
        curve.setSelectedKind(CurvePointKind.allCases[index])
      }
      let tools = NSStackView(views: [addPoint, deletePoint, NSView(), kinds])
      tools.alignment = .centerY
      add(tools)
      let instructions = NSTextField(
        wrappingLabelWithString:
          "Double-click or Add point to add a point on the curve; Delete removes it. Corner points turn sharply; smooth points keep their handles on one line; symmetric handles also match in length. ⌥-click a point to switch corner and smooth, or right-click it. Tab selects points; arrows move them, Shift moves faster."
      )
      instructions.font = DesignerFont.font(size: 10)
      instructions.textColor = .secondaryLabelColor
      add(instructions)
      let selection = label("", size: 10, secondary: true)
      selection.lineBreakMode = .byTruncatingTail
      curve.onSelectionChange = { [unowned curve] in
        selection.stringValue = curve.selectionSummary
        deletePoint.isEnabled = curve.canDeleteSelection
        kinds.isEnabled = curve.canChangeKind
        kinds.selectedSegment =
          curve.selectedKind.flatMap(CurvePointKind.allCases.firstIndex) ?? -1
      }
      add(selection)
      button("Reset curve") { [weak self] in self?.onChange? { $0.haloCurve = HaloCurve() } }
      divider()
      choice("Blur renderer", options: ["Blur", "Regular", "Clear"], path: \.haloMode)
      toggle("Blur underneath panels", \.haloUnderPanels)
      for field in GlassCatalog.halo { number(field) }
    case 2:
      heading(
        "Shadows",
        "The adjustable shadow uses a separate unclipped layer. The system window shadow is visible in the detached preview."
      )
      toggle("System window shadow", \.windowShadow)
      toggle("Custom layer shadow", \.customShadow)
      toggle("Reduced glass shadow radius", \.useReducedShadowRadius)
      for field in GlassCatalog.shadow { number(field) }
    case 3, 4:
      let rim = tabs.selectedSegment == 4
      heading(
        rim ? "Rim highlights" : "Glass background filter",
        "Native values are read from the current glass. Move a slider or edit a number to override it. Uncheck to restore AppKit's value. Unavailable inputs are disabled."
      )
      button("Reset all \(rim ? "rim" : "filter") overrides") { [weak self] in
        self?.onChange? { p in
          if rim { p.highlightInputs = [:] } else { p.filterInputs = [:] }
        }
      }
      for field in rim ? GlassCatalog.highlights : GlassCatalog.filters {
        privateInput(field, rim: rim)
      }
    default:
      heading(
        "Motion",
        "Preview the pop and a second glass surface. Reduce Motion uses a fade and immediate secondary placement."
      )
      choice(
        "Effect", options: ["Emerge", "Unfold", "Pop", "Slide", "Expand"],
        path: \.secondaryEffect, requiresSecondary: true)
      choice("Easing", options: ["Smooth", "Spring"], path: \.secondaryEasing,
        requiresSecondary: true)
      for field in GlassCatalog.motion {
        number(field, requiresSecondary: field.path == \.secondarySeconds)
      }
      button("Play pop   ⌘P") { [weak self] in self?.onPop?() }
      button("Toggle second surface   ⌘T") { [weak self] in self?.onSecondary?() }
    }
    if let lastCanvas { sync(current, canvas: lastCanvas) }
    scroll.contentView.scroll(to: .zero)
  }

  private func add(_ view: NSView) {
    form.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
  }
  private func heading(_ title: String, _ description: String) {
    add(label(title, size: 16, weight: .semibold))
    let help = NSTextField(wrappingLabelWithString: description)
    help.font = DesignerFont.font(size: 10)
    help.textColor = .secondaryLabelColor
    help.preferredMaxLayoutWidth = 300
    add(help)
  }
  private func divider() {
    let box = NSBox()
    box.boxType = .separator
    add(box)
  }
  private func button(_ title: String, _ action: @escaping () -> Void) {
    let button = actionButton(title, target: nil, action: nil)
    sectionActions.bind(button) { _ in action() }
    add(button)
  }
  private func toggle(_ title: String, _ path: WritableKeyPath<GlassParameters, Bool>) {
    let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
    button.font = DesignerFont.font(size: 11)
    sectionActions.bind(button) { [weak self] sender in
      let value = (sender as! NSButton).state == .on
      self?.onChange? { $0[keyPath: path] = value }
    }
    syncs.append { p, _ in button.state = p[keyPath: path] ? .on : .off }
    add(button)
  }
  private func choice(
    _ title: String, options: [String], path: WritableKeyPath<GlassParameters, Int>,
    requiresSecondary: Bool = false
  ) {
    // Segments commit immediately, including native keyboard movement; no pop-up confirmation.
    let control = NSSegmentedControl(
      labels: options, trackingMode: .selectOne, target: nil, action: nil)
    control.controlSize = .small
    control.font = DesignerFont.font(size: 10)
    control.segmentDistribution = .fillEqually
    sectionActions.bind(control) { [weak self] sender in
      let selected = (sender as! NSSegmentedControl).selectedSegment
      guard selected >= 0 else { return }
      self?.onChange? { $0[keyPath: path] = selected }
    }
    let name = label(title, size: 11, weight: .medium)
    syncs.append { p, canvas in
      control.selectedSegment = p[keyPath: path]
      control.isEnabled = !requiresSecondary || canvas.secondaryVisible
      name.textColor = control.isEnabled ? .labelColor : .disabledControlTextColor
    }
    let row = NSStackView(views: [name, control])
    row.spacing = 8
    row.alignment = .centerY
    add(row)
  }

  /// A label line with the value at its right end, and the slider across the full width below.
  /// The value is a borderless text field: it reads as text, and a click edits it exactly.
  private func numericControl(
    title: NSView, range: ClosedRange<Double>, fractionDigits: Int = 2,
    changed: @escaping (Double) -> Void
  )
    -> (header: NSStackView, slider: NSSlider, field: NSTextField)
  {
    let slider = NSSlider(
      value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil,
      action: nil)
    slider.isContinuous = true
    let field = NSTextField()
    field.font = DesignerFont.font(size: 11)
    field.isBordered = false
    field.drawsBackground = false
    field.alignment = .right
    field.textColor = .secondaryLabelColor
    // Return, Tab, and clicking away commit; Escape cancels (see doCommandBy).
    field.cell?.sendsActionOnEndEditing = true
    field.delegate = self
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = fractionDigits
    formatter.minimum = NSNumber(value: range.lowerBound)
    formatter.maximum = NSNumber(value: range.upperBound)
    field.formatter = formatter
    // Wide enough for the longest value a field shows, such as -399.63.
    field.widthAnchor.constraint(equalToConstant: 60).isActive = true
    sectionActions.bind(slider) { sender in
      // The slider replaces whatever was being typed, so the value can follow it.
      if field.currentEditor() != nil { field.abortEditing() }
      changed((sender as! NSSlider).doubleValue)
    }
    sectionActions.bind(field) { sender in
      guard let number = (sender as! NSTextField).objectValue as? NSNumber,
        number.doubleValue.isFinite
      else { return }
      changed(number.doubleValue)
    }
    let header = NSStackView(views: [title, NSView(), field])
    header.alignment = .centerY
    header.spacing = 8
    return (header, slider, field)
  }

  /// Escape cancels a value edit and shows the recipe's value again.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
    control.abortEditing()
    if let lastCanvas { sync(current, canvas: lastCanvas) }
    return true
  }

  /// Stacks rows edge to edge, each spanning the group's width.
  private func group(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let stack = vertical(views, spacing: spacing)
    for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    return stack
  }
  private func number(_ spec: NumericField, requiresSecondary: Bool = false) {
    let title = label(spec.title, size: 11, weight: .medium)
    let (header, slider, field) = numericControl(
      title: title, range: spec.range, fractionDigits: spec.wholePoints ? 0 : 2
    ) { [weak self] value in
      self?.onChange? { $0[keyPath: spec.path] = spec.wholePoints ? value.rounded() : value }
    }
    slider.setAccessibilityLabel(spec.title)
    field.setAccessibilityLabel(spec.title + " value")
    let description = label(spec.help, size: 10, secondary: true)
    syncs.append { p, canvas in
      slider.doubleValue = p[keyPath: spec.path]
      if field.currentEditor() == nil { field.doubleValue = p[keyPath: spec.path] }
      let enabled = !requiresSecondary || canvas.secondaryVisible
      slider.isEnabled = enabled
      field.isEnabled = enabled
      title.textColor = enabled ? .labelColor : .disabledControlTextColor
      description.textColor = enabled ? .secondaryLabelColor : .disabledControlTextColor
    }
    description.lineBreakMode = .byWordWrapping
    description.maximumNumberOfLines = 0
    add(group([header, slider, description], spacing: 3))
  }
  private func privateInput(_ spec: FilterField, rim: Bool) {
    let check = NSButton(checkboxWithTitle: spec.key, target: nil, action: nil)
    let name = spec.key.hasPrefix("input") ? String(spec.key.dropFirst(5)) : spec.key
    let words = name.replacingOccurrences(
      of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    check.title = words.prefix(1).uppercased() + words.dropFirst()
    check.font = DesignerFont.font(size: 10)
    check.cell?.wraps = true
    check.toolTip = spec.help
    let readout = label("Native", size: 10, secondary: true)
    let (header, slider, field) = numericControl(title: check, range: spec.range) {
      [weak self] value in
      self?.onChange? { p in
        if rim { p.highlightInputs[spec.key] = value } else { p.filterInputs[spec.key] = value }
      }
    }
    slider.setAccessibilityLabel(spec.key)
    field.setAccessibilityLabel(spec.key + " value")
    sectionActions.bind(check) { [weak self] sender in
      guard let self else { return }
      let enabled = (sender as! NSButton).state == .on
      let current =
        rim ? lastCanvas?.nativeHighlightInputs[spec.key] : lastCanvas?.nativeFilterInputs[spec.key]
      self.onChange? { p in
        if rim {
          p.highlightInputs[spec.key] = enabled ? current : nil
        } else {
          p.filterInputs[spec.key] = enabled ? current : nil
        }
      }
    }
    syncs.append { p, canvas in
      let override = rim ? p.highlightInputs[spec.key] : p.filterInputs[spec.key]
      let live = rim ? canvas.nativeHighlightInputs[spec.key] : canvas.nativeFilterInputs[spec.key]
      let number = override ?? live
      slider.isEnabled = live != nil
      field.isEnabled = live != nil
      check.isEnabled = live != nil || override != nil
      check.state = override == nil ? .off : .on
      if let number {
        slider.doubleValue = number
        if field.currentEditor() == nil { field.doubleValue = number }
      }
      readout.stringValue =
        live == nil
        ? "Unavailable for this recipe"
        : override == nil ? "Native · \(spec.help)" : "Override · \(spec.help)"
    }
    let checkboxBounds = NSRect(origin: .zero, size: check.intrinsicContentSize)
    let checkboxTextInset = check.cell!.titleRect(forBounds: checkboxBounds).minX
      - check.alignmentRect(forFrame: checkboxBounds).minX
    let hintBounds = NSRect(origin: .zero, size: readout.intrinsicContentSize)
    let hintTextInset = readout.cell!.titleRect(forBounds: hintBounds).minX
      - readout.alignmentRect(forFrame: hintBounds).minX
    let textInset = checkboxTextInset - hintTextInset
    let hint = vertical([readout], spacing: 0)
    hint.edgeInsets.left = textInset
    readout.lineBreakMode = .byWordWrapping
    readout.maximumNumberOfLines = 0
    add(group([header, slider, hint], spacing: 3))
    readout.widthAnchor.constraint(equalTo: hint.widthAnchor, constant: -textInset).isActive = true
  }
}

@MainActor
private final class FlippedView: NSView { override var isFlipped: Bool { true } }
