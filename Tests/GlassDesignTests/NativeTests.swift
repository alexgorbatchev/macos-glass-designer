import AppKit
import XCTest

@testable import GlassDesign

final class NativeTests: XCTestCase {
  @MainActor func testVariantNamesAreUnnumberedAndLabelsAreVerticallyCentered() throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    for browser in [controller.variants, controller.subvariants] {
      let fields = descendants(of: browser).compactMap { $0 as? NSTextField }
      let title = try XCTUnwrap(fields.first {
        $0.stringValue == (browser === controller.variants ? "VARIANTS" : "SUBVARIANTS")
      })
      let shortcut = try XCTUnwrap(fields.first {
        $0.stringValue == (browser === controller.variants ? "⌘L" : "⇧⌘L")
      })
      XCTAssertEqual(
        title.convert(title.bounds, to: browser).midY,
        shortcut.convert(shortcut.bounds, to: browser).midY, accuracy: 0.5)
      XCTAssertFalse(fields.contains {
        $0.stringValue.contains("applies instantly") || $0.stringValue.contains("Type a name")
      })
      for row in 0..<min(5, browser.table.numberOfRows) {
        let cell = try XCTUnwrap(
          browser.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
        cell.layoutSubtreeIfNeeded()
        let text = try XCTUnwrap(cell.textField)
        let expected = browser === controller.variants
          ? ["Default", "Regular", "Clear", "Dock", "App Icons"]
          : ["None", "Lockscreen Controls", "Lockscreen Notifications", "Homescreen Close", "Camera"]
        XCTAssertEqual(text.stringValue, expected[row])
        XCTAssertEqual(
          browser.tableView(browser.table, typeSelectStringFor: nil, row: row), expected[row])
        XCTAssertEqual(text.frame.midY, cell.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(text.frame.height, text.intrinsicContentSize.height, accuracy: 0.5)
        let textRect = text.alignmentRect(forFrame: text.frame)
        XCTAssertEqual(textRect.minX - cell.bounds.minX, 6, accuracy: 0.5)
        XCTAssertEqual(cell.bounds.maxX - textRect.maxX, 6, accuracy: 0.5)
      }
      let row = try XCTUnwrap(
        browser.table.rowView(atRow: browser.table.selectedRow, makeIfNecessary: true))
      let bitmap = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(row.bounds.width), pixelsHigh: Int(row.bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
      let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      context.cgContext.clear(row.bounds)
      row.drawSelection(in: row.bounds)
      NSGraphicsContext.restoreGraphicsState()
      XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.1)
      XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 5, y: 5)).alphaComponent, 0.9)
    }
    let sidebar = try XCTUnwrap(controller.variants.superview as? NSStackView)
    let divider = try XCTUnwrap(sidebar.arrangedSubviews.compactMap { $0 as? NSBox }.first)
    XCTAssertEqual(divider.boxType, .separator)
    XCTAssertEqual(divider.bounds.width, controller.variants.bounds.width, accuracy: 0.5)
    let variantIndex = try XCTUnwrap(sidebar.arrangedSubviews.firstIndex(of: controller.variants))
    let dividerIndex = try XCTUnwrap(sidebar.arrangedSubviews.firstIndex(of: divider))
    let subvariantIndex = try XCTUnwrap(sidebar.arrangedSubviews.firstIndex(of: controller.subvariants))
    XCTAssertLessThan(variantIndex, dividerIndex)
    XCTAssertLessThan(dividerIndex, subvariantIndex)
  }

  @MainActor func testActionsAndReadoutsAreAboveTheMainContent() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    try await waitUntil("native filter readouts") {
      !controller.canvas.nativeFilterInputs.isEmpty
    }
    controller.loadPreset(1)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let views = descendants(of: root)
    let inspector = try XCTUnwrap(views.first { $0 is Inspector })
    let contentTop = inspector.convert(inspector.bounds, to: root).maxY
    let scenes = try XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }.first {
      $0.label(forSegment: 0) == "Desktop"
    })
    let stageControls = try XCTUnwrap(scenes.superview)
    XCTAssertTrue(stageControls.superview === controller.canvas.superview?.superview)
    XCTAssertEqual(
      scenes.convert(scenes.bounds, to: root).minX,
      controller.canvas.convert(controller.canvas.bounds, to: root).minX, accuracy: 0.5)
    XCTAssertGreaterThan(
      scenes.convert(scenes.bounds, to: root).minY,
      controller.canvas.convert(controller.canvas.bounds, to: root).maxY,
      "Scene controls sit above the stage")
    for title in ["Open…", "Save…", "Copy Swift  ⇧⌘C", "Copy JSON", "Paste recipe",
      "Pop  ⌘P", "Second Surface  ⌘T", "Detach  ⌘D"]
    {
      let button = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == title })
      XCTAssertGreaterThan(button.convert(button.bounds, to: root).minY, contentTop, title)
      let cell = try XCTUnwrap(button.cell)
      XCTAssertEqual(cell.titleRect(forBounds: button.bounds).midY, button.bounds.midY,
        accuracy: 0.5, "Button title must be vertically centered: \(title)")
      if let start = title.firstIndex(where: { "⌃⌥⇧⌘".contains($0) }) {
        let text = button.attributedTitle
        let offset = NSRange(start..<title.endIndex, in: title).location
        let actionColor = try XCTUnwrap(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let shortcutColor = try XCTUnwrap(text.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
          let appearance = try XCTUnwrap(NSAppearance(named: name))
          appearance.performAsCurrentDrawingAppearance {
            XCTAssertLessThan(shortcutColor.alphaComponent, actionColor.alphaComponent,
              "Keyboard hint must be dimmer than the action label: \(title)")
          }
        }
      }
    }
    let fields = views.compactMap { $0 as? NSTextField }
    let subtitle = try XCTUnwrap(fields.first {
      $0.stringValue.hasPrefix("Shape the material. Copy the recipe.")
    })
    let version = ProcessInfo.processInfo.operatingSystemVersion
    XCTAssertTrue(
      subtitle.stringValue.contains(
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"),
      "The header must show the running macOS version")
    let appTitle = try XCTUnwrap(fields.first { $0.stringValue == "macOS Glass Designer" })
    XCTAssertTrue(subtitle.superview === appTitle.superview)
    XCTAssertGreaterThan(subtitle.frame.minX, appTitle.frame.maxX)
    func baseline(_ field: NSTextField) -> CGFloat {
      let offset = field.firstBaselineOffsetFromTop
      let y = field.isFlipped ? field.bounds.minY + offset : field.bounds.maxY - offset
      return field.convert(NSPoint(x: 0, y: y), to: root).y
    }
    XCTAssertEqual(
      baseline(appTitle), baseline(subtitle), accuracy: 0.5)
    XCTAssertFalse(fields.contains { $0.stringValue.hasPrefix("Native Liquid Glass") })
    XCTAssertFalse(fields.contains { $0.stringValue == "Preset loaded" })
    controller.change { $0.cornerRadius = 28 }
    XCTAssertFalse(fields.contains { $0.stringValue.contains("filter overrides")
      || $0.stringValue.contains("rim overrides") || $0.stringValue.contains("Live preview") })
    XCTAssertFalse(fields.contains { $0.stringValue.contains("Tab changes focus") })
    let pop = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "Pop  ⌘P" })
    let actions = try XCTUnwrap(pop.superview as? NSStackView)
    for title in ["Open…", "Save…", "Paste recipe", "Copy JSON", "Copy Swift  ⇧⌘C"] {
      let button = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == title })
      XCTAssertTrue(button.superview === actions, title)
    }
    let copy = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
      $0.title == "Copy Swift  ⇧⌘C"
    })
    XCTAssertEqual(copy.alignmentRect(forFrame: copy.frame).maxX, actions.bounds.maxX, accuracy: 0.5)
    let presets = try XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }.first {
      $0.label(forSegment: 0) == "Regular"
    })
    XCTAssertTrue(presets.superview === actions)
    XCTAssertLessThan(presets.frame.maxX, pop.frame.minX)
    XCTAssertEqual(presets.controlSize, pop.controlSize)
    XCTAssertEqual(presets.font?.pointSize, pop.font?.pointSize)
    XCTAssertEqual(
      presets.alignmentRect(forFrame: presets.frame).height,
      pop.alignmentRect(forFrame: pop.frame).height, accuracy: 1)
    let heading = try XCTUnwrap(fields.first { $0.stringValue == "INSPECTOR" })
    let tabs = try XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }.first {
      $0.label(forSegment: 0) == "Surface"
    })
    let shortcut = try XCTUnwrap(fields.first { $0.stringValue == "⌘1–6" })
    XCTAssertEqual(shortcut.convert(shortcut.bounds, to: root).midY,
      heading.convert(heading.bounds, to: root).midY, accuracy: 1)
    XCTAssertEqual(shortcut.superview!.convert(shortcut.alignmentRect(forFrame: shortcut.frame),
      to: inspector).maxX, inspector.bounds.maxX, accuracy: 0.5)
    for index in 0..<6 {
      controller.selectInspector(index)
      XCTAssertEqual(tabs.selectedSegment, index)
    }
    controller.detachPreview()
    controller.detachPreview()
    XCTAssertFalse(fields.contains { $0.stringValue == "Desktop preview closed" })
    XCTAssertEqual(inspector.convert(inspector.bounds, to: root).minY, 14, accuracy: 1)
  }

  /// The surface grows evenly around a fixed centre, so its centred text must not move while a
  /// size slider is dragged slowly. Sizes are whole points: a fractional size would put the
  /// surface's edges, and the text laid out inside it, between device pixels.
  @MainActor func testPreviewTextStaysStillWhileTheSurfaceResizes() throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let canvas = controller.canvas
    let views = descendants(of: root)
    let sliders = try ["Width", "Height"].map { name in
      try XCTUnwrap(views.compactMap { $0 as? NSSlider }.first { $0.accessibilityLabel() == name })
    }
    func title() throws -> CGRect {
      let glass = try XCTUnwrap(canvas.container.contentView?.subviews.first as? NSGlassEffectView)
      let title = try XCTUnwrap(
        descendants(of: try XCTUnwrap(glass.contentView)).compactMap { $0 as? NSTextField }.first)
      return title.convert(title.bounds, to: canvas)
    }
    let start = try title()
    for size in stride(from: 300.0, through: 306.0, by: 0.25) {
      for (slider, value) in zip(sliders, [size + 100, size - 100]) {
        slider.doubleValue = value
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
      }
      XCTAssertEqual(controller.parameters.width, (size + 100).rounded())
      XCTAssertEqual(controller.parameters.height, (size - 100).rounded())
      canvas.layoutSubtreeIfNeeded()
      let moved = try title()
      XCTAssertEqual(moved.midY, start.midY, accuracy: 0.01, "height \(size - 100)")
      XCTAssertEqual(moved.midX, start.midX, accuracy: 0.01, "width \(size + 100)")
    }
    let field = try XCTUnwrap(
      views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Height value" })
    field.stringValue = "250.4"
    XCTAssertTrue(field.sendAction(field.action, to: field.target))
    XCTAssertEqual(controller.parameters.height, 250, "Typed sizes round to whole points")
    XCTAssertEqual(field.stringValue, "250")
  }

  /// The panel gap places the second surface, so it is whole points too: the second surface's
  /// text moves exactly with the gap instead of wobbling between device pixels.
  @MainActor func testSecondSurfaceTextFollowsThePanelGapInWholePoints() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.change {
      $0.secondaryEffect = 3
      $0.secondarySeconds = 0.05
      $0.haloEnabled = false
    }
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let canvas = controller.canvas
    controller.toggleSecondary()
    try await waitUntil("the second surface to settle") {
      canvas.secondaryVisible && !canvas.secondaryAnimating
    }
    let slider = try XCTUnwrap(
      descendants(of: root).compactMap { $0 as? NSSlider }.first {
        $0.accessibilityLabel() == "Panel gap"
      })
    func title() throws -> CGRect {
      let glass = try XCTUnwrap(canvas.container.contentView?.subviews.last as? NSGlassEffectView)
      let title = try XCTUnwrap(
        descendants(of: try XCTUnwrap(glass.contentView)).compactMap { $0 as? NSTextField }.first)
      return title.convert(title.bounds, to: canvas)
    }
    let startGap = controller.parameters.panelGap
    let start = try title()
    for gap in stride(from: 10.0, through: 14.0, by: 0.25) {
      slider.doubleValue = gap
      XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
      XCTAssertEqual(controller.parameters.panelGap, gap.rounded())
      canvas.layoutSubtreeIfNeeded()
      XCTAssertEqual(
        try title().midY, start.midY + gap.rounded() - startGap, accuracy: 0.01, "gap \(gap)")
    }
  }

  @MainActor func testPreviewTextIsCenteredAndSecondSurfaceControlsFollowVisibility() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let glass = try XCTUnwrap(controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
    let sample = try XCTUnwrap(glass.contentView)
    let text = descendants(of: sample).compactMap { $0 as? NSTextField }
    XCTAssertEqual(text.count, 2)
    for field in text {
      XCTAssertEqual(field.alignment, .center, field.stringValue)
      XCTAssertEqual(field.convert(field.bounds, to: sample).midX, sample.bounds.midX,
        accuracy: 0.5, field.stringValue)
    }
    controller.change { $0.secondarySeconds = 0.05 }
    func checkControls(enabled: Bool) throws {
      for (tab, labels) in [(0, ["Merge distance", "Panel gap"]), (5, ["Second duration"])] {
        controller.selectInspector(tab)
        for title in labels {
          let slider = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSSlider }.first {
            $0.accessibilityLabel() == title
          })
          let field = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == title + " value"
          })
          XCTAssertEqual(slider.isEnabled, enabled, title)
          XCTAssertEqual(field.isEnabled, enabled, title)
        }
      }
      for title in ["Effect", "Easing"] {
        let label = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSTextField }.first {
          $0.stringValue == title
        })
        let control = try XCTUnwrap(label.superview?.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        XCTAssertEqual(control.isEnabled, enabled, title)
      }
      let pop = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSSlider }.first {
        $0.accessibilityLabel() == "Pop duration"
      })
      XCTAssertTrue(pop.isEnabled)
    }
    try checkControls(enabled: false)
    let toggle = try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first {
      $0.title == "Second Surface  ⌘T"
    })
    toggle.performClick(nil)
    XCTAssertTrue(controller.canvas.secondaryVisible)
    try checkControls(enabled: true)
    try await waitUntil("the second surface to settle") { !controller.canvas.secondaryAnimating }
    toggle.performClick(nil)
    XCTAssertFalse(controller.canvas.secondaryVisible)
    try checkControls(enabled: false)
  }

  @MainActor func testInspectorUsesCompactRowsMapleMonoAndRoundedDisplayWithoutLosingPrecision()
    throws
  {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.change { $0.cornerRadius = 23.718281828 }
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let fields = descendants(of: root).compactMap { $0 as? NSTextField }
    let value = try XCTUnwrap(fields.first { $0.accessibilityLabel() == "Corner radius value" })
    XCTAssertEqual(value.stringValue, "23.72")
    let title = try XCTUnwrap(fields.first { $0.stringValue == "Corner radius" })
    let titleRect = title.convert(title.bounds, to: root)
    let row = try XCTUnwrap(value.superview)
    let rowRect = row.convert(row.bounds, to: root)
    XCTAssertEqual(titleRect.midY, rowRect.midY, accuracy: 1)
    XCTAssertEqual(controller.parameters.cornerRadius, 23.718281828)
    // Typing a value sets the recipe exactly; the display rounds only what it shows.
    value.stringValue = "19.375"
    XCTAssertTrue(value.sendAction(value.action, to: value.target))
    XCTAssertEqual(controller.parameters.cornerRadius, 19.375)
    controller.change { $0.cornerRadius = 23.718281828 }
    let swift = try SwiftExport.source(for: controller.parameters, nativeFilterInputs: [:])
    XCTAssertTrue(swift.contains("23.718281828"))
    XCTAssertTrue(swift.contains("var secondaryEffect:"))
    XCTAssertFalse(swift.contains("correction"))
    for index in 0..<6 {
      controller.selectInspector(index)
      root.layoutSubtreeIfNeeded()
      // Each slider spans its row beneath the label; the value sits at the label line's right end.
      func box(_ view: NSView) -> CGRect {
        view.convert(view.alignmentRect(forFrame: view.bounds), to: root)
      }
      let views = descendants(of: root)
      for slider in views.compactMap({ $0 as? NSSlider }) {
        let name = try XCTUnwrap(slider.accessibilityLabel())
        let field = try XCTUnwrap(
          views.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == name + " value" },
          name)
        let title = try XCTUnwrap((field.superview as? NSStackView)?.arrangedSubviews.first, name)
        XCTAssertEqual(box(slider).minX, box(title).minX, accuracy: 1, "\(name) starts at its label")
        XCTAssertEqual(box(slider).maxX, box(field).maxX, accuracy: 1, "\(name) ends at its value")
        XCTAssertGreaterThan(box(slider).width, 300, "\(name) takes the row width")
        XCTAssertLessThan(box(slider).midY, box(title).minY, "\(name) sits below its label")
        XCTAssertEqual(box(field).midY, box(title).midY, accuracy: 1, "\(name) value is on the label line")
      }
      for view in descendants(of: root) {
        guard view is NSTextField || view is NSButton || view is NSSegmentedControl,
          let control = view as? NSControl
        else { continue }
        if let text = control as? NSTextField, !text.stringValue.isEmpty {
          let attributed = text.attributedStringValue
          // Attributed fonts determine rendering; the field's default font may differ.
          attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) {
            value, _, _ in
            let font = value as? NSFont ?? text.font
            XCTAssertEqual(font?.familyName, "Maple Mono", "\(type(of: view))")
          }
        } else {
          XCTAssertEqual(control.font?.familyName, "Maple Mono", "\(type(of: view))")
        }
        if (index == 3 || index == 4), let check = control as? NSButton,
          let row = check.superview as? NSStackView,
          row.arrangedSubviews.contains(where: { ($0 as? NSTextField)?.isEditable == true })
        {
          XCTAssertEqual(check.title.first?.isUppercase, true, check.title)
          let group = try XCTUnwrap(row.superview)
          let hint = try XCTUnwrap(descendants(of: group).compactMap { $0 as? NSTextField }.first {
            $0.stringValue.hasPrefix("Native ·") || $0.stringValue.hasPrefix("Override ·")
              || $0.stringValue == "Unavailable for this recipe"
          })
          let checkCell = try XCTUnwrap(check.cell)
          let hintCell = try XCTUnwrap(hint.cell)
          XCTAssertEqual(
            hint.convert(hintCell.titleRect(forBounds: hint.bounds), to: root).minX,
            check.convert(checkCell.titleRect(forBounds: check.bounds), to: root).minX,
            accuracy: 0.5, "Hint must align with the checkbox text: \(check.title)")
        }
        if let title = view as? NSTextField, !title.isEditable,
          let row = title.superview as? NSStackView,
          row.arrangedSubviews.contains(where: {
            $0 is NSSlider || $0 is NSSegmentedControl || ($0 as? NSTextField)?.isEditable == true
          })
        {
          XCTAssertGreaterThanOrEqual(
            title.bounds.width + 1, title.intrinsicContentSize.width,
            "Control label must fit: \(title.stringValue)")
        }
      }
    }
  }

  @MainActor func testCornerSliderUpdatesNativeGeometryDuringTracking() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    controller.change { $0.haloEnabled = false }
    try await waitUntil("native filter readouts") {
      !controller.canvas.nativeFilterInputs.isEmpty
    }
    let slider = try XCTUnwrap(
      descendants(of: controller.window.contentView!).compactMap { $0 as? NSSlider }
        .first { $0.accessibilityLabel() == "Corner radius" })
    XCTAssertTrue(slider.isContinuous)
    for radius in [0.0, 40.5, 90.0] {
      slider.doubleValue = radius
      XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
      XCTAssertEqual(controller.parameters.cornerRadius, radius)
      let glass = try XCTUnwrap(
        controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
      XCTAssertEqual(glass.cornerRadius, radius)
      serviceSliderTracking()
      controller.window.displayIfNeeded()
      let shapes = PrivateGlass.layers(controller.canvas.container.layer).filter {
        NSStringFromClass(type(of: $0)) == "CASDFElementLayer" && !$0.isHidden
      }
      XCTAssertFalse(shapes.isEmpty)
      for shape in shapes {
        XCTAssertEqual(
          shape.cornerRadius, radius, accuracy: 0.001,
          "Native glass geometry must redraw before the slider is released")
      }
    }
  }

  @MainActor private func serviceSliderTracking() {
    let deadline = Date(timeIntervalSinceNow: 0.08)
    let timer = Timer(fire: deadline, interval: 0, repeats: false) { _ in }
    RunLoop.current.add(timer, forMode: .eventTracking)
    RunLoop.current.run(mode: .eventTracking, before: deadline)
  }

  @MainActor func testFilterAndHaloOverridesApplyBeforeSliderTrackingEnds() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.loadPreset(2)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    try await waitUntil("native filter readouts") {
      !controller.canvas.nativeFilterInputs.isEmpty
    }
    controller.change {
      $0.filterInputs["inputBlurRadius"] = 7.125
      $0.haloBlurRadius = 23.5
    }
    serviceSliderTracking()
    XCTAssertEqual(liveFilterInput(controller.canvas, "inputBlurRadius"), 7.125)
    var issues: [String] = []
    let halo = try XCTUnwrap(
      PrivateGlass.layers(controller.canvas.layer).first { layer in
        (layer.filters as? [NSObject])?.contains {
          PrivateGlass.read($0, "name", issues: &issues) as? String == "variableBlur"
        } == true
      })
    let radius = try XCTUnwrap(
      PrivateGlass.read(halo, "filters.variableBlur.inputRadius", issues: &issues) as? NSNumber)
    XCTAssertEqual(radius.doubleValue, 23.5)
    XCTAssertEqual(issues, [])
  }

  @MainActor func testReadoutsAndExportKeepNativeValuesWhileOverridesApply() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.change { $0.haloEnabled = false }
    let canvas = controller.canvas
    try await waitUntil("native filter and rim readouts") {
      !canvas.nativeFilterInputs.isEmpty && !canvas.nativeHighlightInputs.isEmpty
    }
    let nativeBlur = try XCTUnwrap(canvas.nativeFilterInputs["inputBlurRadius"])
    let nativeKey = try XCTUnwrap(canvas.nativeHighlightInputs["keyAmount"])
    // Two successive overrides: the second readout must not report the first override.
    for (blur, key) in [(nativeBlur + 1, nativeKey + 0.25), (nativeBlur + 5, nativeKey + 0.5)] {
      controller.change {
        $0.filterInputs["inputBlurRadius"] = blur
        $0.highlightInputs["keyAmount"] = key
      }
      canvas.refreshInternals()
      XCTAssertEqual(liveFilterInput(canvas, "inputBlurRadius"), blur)
      XCTAssertEqual(try XCTUnwrap(liveHighlightInput(canvas, "keyAmount")), key, accuracy: 0.00001)
      XCTAssertEqual(canvas.nativeFilterInputs["inputBlurRadius"], nativeBlur)
      XCTAssertEqual(canvas.nativeHighlightInputs["keyAmount"], nativeKey)
    }
    let board = NSPasteboard(name: .init("GlassDesignerTests.\(UUID())"))
    defer { board.releaseGlobally() }
    controller.writeSwift(to: board)
    let source = try XCTUnwrap(board.string(forType: .string))
    XCTAssertTrue(
      source.contains("// Native glassBackground.inputBlurRadius = \(nativeBlur)"), source)
    XCTAssertTrue(source.contains("var filterInputs: [String: Double] = [\"inputBlurRadius\": \(nativeBlur + 5)]"))
  }

  @MainActor func testStatusLineClearsIssuesThatNoLongerApply() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    // Before the window is displayed AppKit has not built the glass layers.
    controller.canvas.refreshInternals()
    XCTAssertFalse(controller.canvas.issues.isEmpty)
    XCTAssertEqual(controller.status.stringValue, controller.canvas.issues.joined(separator: " · "))
    XCTAssertEqual(controller.status.toolTip, controller.status.stringValue)
    controller.window.orderFront(nil)
    try await waitUntil("the issue to resolve") { controller.canvas.issues.isEmpty }
    XCTAssertEqual(controller.status.stringValue, "")
    XCTAssertNil(controller.status.toolTip)
  }

  @MainActor func testTintAndFillRenderRecipeHSBAInSRGB() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.change {
      ($0.tintHue, $0.tintSaturation, $0.tintBrightness, $0.tintAlpha) = (0.3, 0.7, 0.8, 0.5)
      ($0.fillHue, $0.fillSaturation, $0.fillBrightness, $0.fillAlpha) = (0.3, 0.7, 0.8, 1)
      $0.fillInside = false
    }
    controller.canvas.layoutSubtreeIfNeeded()
    // sRGB HSB (0.3, 0.7, 0.8) is RGB (0.352, 0.8, 0.24); Generic RGB would differ.
    func assertSRGB(_ color: NSColor?, alpha: Double, line: UInt = #line) throws {
      let srgb = try XCTUnwrap(color?.usingColorSpace(.sRGB), line: line)
      for (actual, expected) in [
        (srgb.redComponent, 0.352), (srgb.greenComponent, 0.8), (srgb.blueComponent, 0.24),
        (srgb.alphaComponent, alpha),
      ] {
        XCTAssertEqual(actual, expected, accuracy: 0.002, line: line)
      }
    }
    let glass = try XCTUnwrap(
      controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
    try assertSRGB(glass.tintColor, alpha: 0.5)
    func fills() -> [CALayer] {
      PrivateGlass.layers(controller.canvas.layer).filter {
        $0.name == "designer.fill" && $0.backgroundColor?.alpha == 1
      }
    }
    try await waitUntil("opaque fill layers") { !fills().isEmpty }
    for fill in fills() {
      try assertSRGB(fill.backgroundColor.flatMap(NSColor.init(cgColor:)), alpha: 1)
    }
  }

  @MainActor func testDetachedPreviewKeepsBothRequestedShadowsAndFitsHalo() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer {
      controller.window.orderOut(nil)
      controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    }
    controller.change {
      $0.windowShadow = true
      $0.customShadow = true
      $0.haloEnabled = true
    }
    controller.detachPreview()
    let preview = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Glass desktop preview" && $0.isVisible })
    let canvas = try XCTUnwrap(preview.contentView as? GlassCanvas)
    XCTAssertTrue(
      preview.hasShadow, "The system shadow checkbox must remain independent of the custom shadow")
    XCTAssertFalse(preview.isOpaque)
    controller.change { $0.windowTitled = true }
    XCTAssertTrue(preview.styleMask.contains(.titled))
    controller.change { $0.glassEnabled = false }
    XCTAssertTrue(canvas.container.isHidden)
    controller.change {
      $0.glassEnabled = true
      $0.windowTitled = false
    }
    XCTAssertFalse(canvas.container.isHidden)
    XCTAssertFalse(preview.styleMask.contains(.titled))
    for mode in 0...2 {
      controller.change { $0.haloMode = mode }
      try await waitUntil(
        "halo mode \(mode) without issues", detail: { canvas.issues.joined(separator: "; ") }
      ) { canvas.activeHaloMode == mode && !canvas.nativeFilterInputs.isEmpty && canvas.issues.isEmpty }
    }
    controller.toggleSecondary()
    try await waitUntil("the expansion to settle") {
      canvas.secondaryVisible && !canvas.secondaryAnimating
    }
    let expanded = canvas.visibleSurfaceBounds.insetBy(
      dx: -controller.parameters.haloMargin, dy: -controller.parameters.haloMargin)
    XCTAssertTrue(
      canvas.bounds.contains(expanded),
      "Detached preview must include the full halo around expansion")
    controller.change { $0.panelGap = 40 }
    XCTAssertEqual(canvas.mainSurfaceFrame.height, controller.parameters.height + 80 + 40)
    XCTAssertTrue(canvas.issues.isEmpty, canvas.issues.joined(separator: "; "))
  }

  /// Background dragging needs the clicks: a transparent window otherwise lets them fall
  /// through to the window below wherever its pixels are clear, which includes glass.
  @MainActor func testDetachedPreviewReceivesClicksSoItCanBeDragged() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer {
      controller.window.orderOut(nil)
      controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    }
    controller.window.orderFront(nil)
    controller.change { $0.haloEnabled = false }
    controller.detachPreview()
    let preview = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Glass desktop preview" && $0.isVisible })
    let canvas = try XCTUnwrap(preview.contentView as? GlassCanvas)
    XCTAssertTrue(preview.isMovableByWindowBackground)
    try await waitUntil("the preview's glass") { !canvas.nativeFilterInputs.isEmpty }
    let glass = canvas.mainSurfaceFrame
    for (name, point) in [
      ("glass", CGPoint(x: glass.midX, y: glass.midY)),
      ("margin", CGPoint(x: glass.minX - 8, y: glass.midY)),
    ] {
      try await waitUntil("the window server to route \(name) clicks to the preview") {
        NSWindow.windowNumber(
          at: preview.convertPoint(toScreen: point), belowWindowWithWindowNumber: 0)
          == preview.windowNumber
      }
    }
  }

  @MainActor func testShadowFollowsAnInFlightExpansion() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    controller.change {
      $0.secondarySeconds = 1
      $0.haloEnabled = false
      $0.customShadow = true
    }
    let before = controller.canvas.mainSurfaceFrame
    controller.toggleSecondary()
    try await waitUntil("the shadow to follow the moving expansion") {
      controller.canvas.mainSurfaceFrame.height > before.height
        && shadowIsAttached(controller.canvas)
    }
    XCTAssertTrue(controller.canvas.secondaryAnimating)
    XCTAssertLessThan(controller.canvas.mainSurfaceFrame.height, before.height + 90)
    // A parameter edit during motion replaces the animated recipe and settles geometry.
    controller.change { $0.cornerRadius = 24.5 }
    try await waitUntil("the edited expansion to settle") {
      !controller.canvas.secondaryAnimating
        && controller.canvas.mainSurfaceFrame.height == before.height + 90
    }
    assertShadowAttached(controller.canvas)
  }

  @MainActor func testHaloMaskTracksCurveOrientationAndPanelHoles() throws {
    var p = GlassParameters()
    p.haloCurve.nodes[0].outgoing = CurvePoint(x: 0.25, y: 0.25)
    p.haloCurve.nodes[1].incoming = CurvePoint(x: 0.75, y: 0.75)
    p.haloMargin = 50
    let size = CGSize(width: 700, height: 600)
    let scale = 2.0
    /// Mask alpha at a point in view coordinates (origin bottom-left), independent of pixel format.
    func alpha(_ image: CGImage, _ x: Double, _ y: Double) throws -> Double {
      let context = try XCTUnwrap(
        CGContext(
          data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
          bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
      let row = image.height - 1 - Int(y * scale)
      return Double(bytes[row * context.bytesPerRow + Int(x * scale) * 4 + 3]) / 255
    }
    // The panel sits low in the canvas, so a vertically flipped mask fails the samples below.
    let panel = CGRect(x: 140, y: 100, width: 420, height: 200)
    let image = try XCTUnwrap(HaloMask.make(size: size, panels: [panel], p: p, scale: scale))
    XCTAssertEqual(image.bitsPerPixel, 8, "Masks carry alpha only")
    XCTAssertEqual(try alpha(image, 350, 200), 1, accuracy: 0.01)
    XCTAssertEqual(try alpha(image, 350, 310), p.haloCurve.value(at: 0.8), accuracy: 0.02)
    XCTAssertEqual(try alpha(image, 350, 60), p.haloCurve.value(at: 0.2), accuracy: 0.02)
    XCTAssertEqual(try alpha(image, 350, 500), 0, accuracy: 0.01)
    XCTAssertEqual(try alpha(image, 120, 200), p.haloCurve.value(at: 0.6), accuracy: 0.02)

    // Two panels: the halo surrounds their group; without under-panel blur each panel is cut out.
    let lower = CGRect(x: 140, y: 100, width: 420, height: 150)
    let upper = CGRect(x: 140, y: 290, width: 420, height: 80)
    p.haloUnderPanels = false
    let cutout = try XCTUnwrap(HaloMask.make(size: size, panels: [lower, upper], p: p, scale: scale))
    XCTAssertEqual(try alpha(cutout, 350, 175), 0, accuracy: 0.01)
    XCTAssertEqual(try alpha(cutout, 350, 330), 0, accuracy: 0.01)
    XCTAssertEqual(try alpha(cutout, 350, 270), 1, accuracy: 0.01, "The gap stays at full strength")
    XCTAssertEqual(try alpha(cutout, 350, 395), p.haloCurve.value(at: 0.5), accuracy: 0.02)

    p.haloMargin = 160
    let start = ContinuousClock.now
    _ = try XCTUnwrap(
      HaloMask.make(size: CGSize(width: 900, height: 800), panels: [lower, upper], p: p, scale: 2))
    print("Halo mask generation: \(start.duration(to: .now)) for 900×800 pt, 160 pt margin, at 2×")
  }

  @MainActor func testSecondaryMotionKeepsMainSurfaceAnchoredAndShadowAttached() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    for effect in 0...4 {
      controller.change {
        $0.secondaryEffect = effect
        $0.customShadow = true
        $0.haloEnabled = false
      }
      let origin = controller.canvas.mainSurfaceFrame.origin
      controller.toggleSecondary()
      try await waitUntil("effect \(effect) to show") { !controller.canvas.secondaryAnimating }
      XCTAssertEqual(
        controller.canvas.mainSurfaceFrame.origin, origin,
        "Effect \(effect) must keep the main surface anchored")
      assertShadowAttached(controller.canvas)
      controller.toggleSecondary()
      try await waitUntil("effect \(effect) to hide") { !controller.canvas.secondaryAnimating }
      XCTAssertEqual(controller.canvas.mainSurfaceFrame.origin, origin)
      assertShadowAttached(controller.canvas)
    }
  }

  @MainActor private func assertShadowAttached(
    _ canvas: GlassCanvas, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(
      shadowIsAttached(canvas),
      "Shadow \(String(describing: canvas.shadowBounds)) must outline \(canvas.visibleSurfaceBounds)",
      file: file, line: line)
  }

  func testArrowSelectionAppliesImmediatelyAndPreservesKeyboardFocus() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = DesignerController()
      defer { controller.window.orderOut(nil) }
      controller.window.contentView?.layoutSubtreeIfNeeded()
      controller.window.makeFirstResponder(controller.variants.table)
      let down = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [],
          timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
          characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}", isARepeat: false,
          keyCode: 125))
      controller.variants.table.keyDown(with: down)
      XCTAssertEqual(
        controller.parameters.variant, 2, "Down must apply clear immediately, with no Enter")
      XCTAssertTrue(controller.window.firstResponder === controller.variants.table)
      controller.window.makeFirstResponder(controller.subvariants.table)
      controller.subvariants.table.keyDown(with: down)
      XCTAssertEqual(controller.parameters.subvariant, "lockscreenControls")
      XCTAssertTrue(controller.window.firstResponder === controller.subvariants.table)
      for _ in 0..<40 { controller.subvariants.table.keyDown(with: down) }
      XCTAssertEqual(controller.parameters.subvariant, "iOSNotificationCenter")
    }
  }

  func testClipboardSwiftAndEmbeddedJSONDescribeTheSameRecipe() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = DesignerController()
      defer { controller.window.orderOut(nil) }
      controller.change { p in
        p.cornerRadius = 23.718281828
        p.tintHue = 0.3
        p.tintSaturation = 0.7
        p.tintBrightness = 0.8
        p.tintAlpha = 0.15
        p.filterInputs["inputBlurRadius"] = 4.125
      }
      let board = NSPasteboard(name: .init("GlassDesignerTests.\(UUID())"))
      defer { board.releaseGlobally() }
      controller.writeSwift(to: board)
      let source = try XCTUnwrap(board.string(forType: .string))
      XCTAssertTrue(source.contains("23.718281828"))
      XCTAssertTrue(source.contains("var tintHue: Double = 0.3"))
      let data = try XCTUnwrap(board.data(forType: .glassRecipe))
      XCTAssertEqual(try GlassDocument.load(data).parameters, controller.parameters)
    }
  }

  func testInvalidImportDoesNotMutateCurrentRecipe() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = DesignerController()
      defer { controller.window.orderOut(nil) }
      controller.change { $0.cornerRadius = 23.5 }
      let before = controller.parameters
      var document = GlassDocument(parameters: GlassParameters())
      document.parameters.interactionState = 100
      controller.importData(try JSONEncoder().encode(document))
      XCTAssertEqual(controller.parameters, before)
    }
  }

  @MainActor func testNativeRenderingAndLayoutAcrossInspectors() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    let content = try XCTUnwrap(controller.window.contentView)
    XCTAssertEqual(content.bounds.width, 1576, accuracy: 0.001)
    XCTAssertEqual(content.bounds.height, 830, accuracy: 0.001)
    XCTAssertFalse(controller.window.styleMask.contains(.resizable))
    let inspector = try XCTUnwrap(descendants(of: content).first { $0 is Inspector })
    let inspectorBounds = inspector.convert(inspector.bounds, to: content)
    let columns = try XCTUnwrap(inspector.superview as? NSStackView)
    let sidebar = try XCTUnwrap(controller.variants.superview)
    let sidebarBounds = sidebar.convert(sidebar.bounds, to: content)
    let canvasBounds = controller.canvas.convert(controller.canvas.bounds, to: content)
    XCTAssertEqual(canvasBounds.minX, sidebarBounds.maxX + columns.spacing, accuracy: 0.5)
    XCTAssertEqual(
      canvasBounds.maxX, inspectorBounds.minX - columns.spacing, accuracy: 0.5,
      "The stage must take the space between the sidebar and the inspector")
    XCTAssertEqual(
      inspectorBounds.maxX, columns.convert(columns.bounds, to: content).maxX, accuracy: 1,
      "The inspector must sit at the right edge of the columns")
    try await waitUntil("native filter and rim readouts") {
      !controller.canvas.nativeFilterInputs.isEmpty
        && !controller.canvas.nativeHighlightInputs.isEmpty
    }
    XCTAssertTrue(
      controller.canvas.issues.isEmpty, controller.canvas.issues.joined(separator: "; "))
    XCTAssertNotNil(controller.canvas.nativeFilterInputs["inputBlurRadius"])
    XCTAssertNotNil(controller.canvas.nativeHighlightInputs["keyAmount"])
    let capturing = ProcessInfo.processInfo.environment["GLASS_CAPTURE"] == "1"
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".tmp/verification")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if capturing {
      NSApp.setActivationPolicy(.regular)
      controller.show()
      NSApp.activate()
    }
    for index in 0..<6 {
      controller.selectInspector(index)
      controller.window.contentView?.layoutSubtreeIfNeeded()
      XCTAssertFalse(controller.window.contentView!.hasAmbiguousLayout)
      if capturing {
        // The window server composites glass asynchronously; captures only need it to settle.
        try await Task.sleep(for: .milliseconds(200))
        try capture(
          controller.window, to: directory.appendingPathComponent("inspector-\(index).png"))
      }
    }
    // Change a private filter using the real layer, then remove it and require the native recipe.
    let native = try XCTUnwrap(controller.canvas.nativeFilterInputs["inputBlurRadius"])
    controller.change { $0.filterInputs["inputBlurRadius"] = 9.125 }
    try await waitUntil("the override on the live layer") {
      liveFilterInput(controller.canvas, "inputBlurRadius") == 9.125
    }
    controller.change { $0.filterInputs = [:] }
    try await waitUntil("the native value on the rebuilt layer") {
      liveFilterInput(controller.canvas, "inputBlurRadius") == native
    }
    XCTAssertEqual(controller.canvas.nativeFilterInputs["inputBlurRadius"], native)

    let source = try SwiftExport.source(
      for: controller.parameters, nativeFilterInputs: controller.canvas.nativeFilterInputs)
    try assertExportCompiles(source, named: "DesignedGlass")
    print(
      "Native probe: filters=\(controller.canvas.nativeFilterInputs.count) rim=\(controller.canvas.nativeHighlightInputs.count) issues=\(controller.canvas.issues)"
    )
  }

  @MainActor private func capture(_ window: NSWindow, to url: URL) throws {
    // Capture this test's own window. View bitmap caching cannot capture compositor glass.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(
      process.terminationStatus, 0, "Window capture requires Screen Recording permission")
  }

  @MainActor func testPrivateRecipesAndOverrideReadback() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    var issues: [String] = []
    for variant in GlassCatalog.variants.indices {
      controller.change {
        $0.variant = variant
        $0.haloEnabled = false
      }
      let glass = try XCTUnwrap(
        controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
      XCTAssertEqual(
        (PrivateGlass.read(glass, "_variant", issues: &issues) as? NSNumber)?.intValue, variant)
    }
    controller.loadPreset(1)
    for subvariant in GlassCatalog.subvariants {
      controller.change { $0.subvariant = subvariant }
      let glass = try XCTUnwrap(
        controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
      XCTAssertEqual(PrivateGlass.read(glass, "_subvariant", issues: &issues) as? String, subvariant)
    }
    XCTAssertEqual(issues, [])
    controller.loadPreset(0)
    try await waitUntil("native rim readouts") {
      !controller.canvas.nativeHighlightInputs.isEmpty
    }
    let nativeRim = controller.canvas.nativeHighlightInputs
    controller.change { p in
      for field in GlassCatalog.filters {
        p.filterInputs[field.key] = (field.range.lowerBound + field.range.upperBound) / 2
      }
      for field in GlassCatalog.highlights { p.highlightInputs[field.key] = 0.625 }
    }
    let canvas = controller.canvas
    let parameters = controller.parameters
    try await waitUntil("every override on the live layers") {
      parameters.filterInputs.allSatisfy { key, value in
        liveFilterInput(canvas, key).map { abs($0 - value) < 0.00001 } == true
      }
        && parameters.highlightInputs.allSatisfy { key, value in
          liveHighlightInput(canvas, key).map { abs($0 - value) < 0.00001 } == true
        }
    }
    controller.change {
      $0.highlightInputs = [:]
      $0.filterInputs = [:]
    }
    try await waitUntil("native rim readouts after removing overrides") {
      !controller.canvas.nativeHighlightInputs.isEmpty
    }
    XCTAssertEqual(controller.canvas.nativeHighlightInputs, nativeRim)
    XCTAssertTrue(
      controller.canvas.issues.isEmpty, controller.canvas.issues.joined(separator: "; "))
  }
}
