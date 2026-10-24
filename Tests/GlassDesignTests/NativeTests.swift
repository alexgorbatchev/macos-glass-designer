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
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    for browser in [controller.variants, controller.subvariants] {
      let fields = descendants(browser).compactMap { $0 as? NSTextField }
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
    try await Task.sleep(for: .milliseconds(150))
    controller.canvas.refreshInternals()
    controller.loadPreset(1)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let views = descendants(root)
    let inspector = try XCTUnwrap(views.first { $0 is Inspector })
    let contentTop = inspector.convert(inspector.bounds, to: root).maxY
    let backgrounds = try XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }.first {
      $0.label(forSegment: 0) == "Landscape"
    })
    XCTAssertTrue(backgrounds.superview === controller.canvas.superview?.superview)
    XCTAssertEqual(
      backgrounds.convert(backgrounds.bounds, to: root).minX,
      controller.canvas.convert(controller.canvas.bounds, to: root).minX, accuracy: 0.5)
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
    XCTAssertEqual(
      subtitle.stringValue,
      "Shape the material. Copy the recipe. macOS v\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
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
      let item = NSMenuItem()
      item.tag = index
      controller.inspectorTab(item)
      XCTAssertEqual(tabs.selectedSegment, index)
    }
    controller.detachPreview()
    controller.detachPreview()
    XCTAssertFalse(fields.contains { $0.stringValue == "Desktop preview closed" })
    XCTAssertEqual(inspector.convert(inspector.bounds, to: root).minY, 14, accuracy: 1)
  }

  @MainActor func testPreviewTextIsCenteredAndSecondSurfaceControlsFollowVisibility() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let glass = try XCTUnwrap(controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
    let sample = try XCTUnwrap(glass.contentView)
    let text = descendants(sample).compactMap { $0 as? NSTextField }
    XCTAssertEqual(text.count, 2)
    for field in text {
      XCTAssertEqual(field.alignment, .center, field.stringValue)
      XCTAssertEqual(field.convert(field.bounds, to: sample).midX, sample.bounds.midX,
        accuracy: 0.5, field.stringValue)
    }
    controller.change { $0.secondarySeconds = 0.05 }
    func checkControls(enabled: Bool) throws {
      for (tab, labels) in [(0, ["Merge distance", "Panel gap"]), (5, ["Second duration"])] {
        let item = NSMenuItem()
        item.tag = tab
        controller.inspectorTab(item)
        for title in labels {
          let slider = try XCTUnwrap(descendants(root).compactMap { $0 as? NSSlider }.first {
            $0.accessibilityLabel() == title
          })
          let field = try XCTUnwrap(descendants(root).compactMap { $0 as? NSTextField }.first {
            $0.accessibilityLabel() == title + " value"
          })
          XCTAssertEqual(slider.isEnabled, enabled, title)
          XCTAssertEqual(field.isEnabled, enabled, title)
        }
      }
      for title in ["Effect", "Easing"] {
        let label = try XCTUnwrap(descendants(root).compactMap { $0 as? NSTextField }.first {
          $0.stringValue == title
        })
        let control = try XCTUnwrap(label.superview?.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        XCTAssertEqual(control.isEnabled, enabled, title)
      }
      let pop = try XCTUnwrap(descendants(root).compactMap { $0 as? NSSlider }.first {
        $0.accessibilityLabel() == "Pop duration"
      })
      XCTAssertTrue(pop.isEnabled)
    }
    try checkControls(enabled: false)
    let toggle = try XCTUnwrap(descendants(root).compactMap { $0 as? NSButton }.first {
      $0.title == "Second Surface  ⌘T"
    })
    toggle.performClick(nil)
    XCTAssertTrue(controller.canvas.secondaryVisible)
    try checkControls(enabled: true)
    try await Task.sleep(for: .milliseconds(180))
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
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let fields = descendants(root).compactMap { $0 as? NSTextField }
    let value = try XCTUnwrap(fields.first { $0.accessibilityLabel() == "Corner radius value" })
    XCTAssertEqual(value.stringValue, "23.72")
    let title = try XCTUnwrap(fields.first { $0.stringValue == "Corner radius" })
    let titleRect = title.convert(title.bounds, to: root)
    let row = try XCTUnwrap(value.superview)
    let rowRect = row.convert(row.bounds, to: root)
    XCTAssertEqual(titleRect.midY, rowRect.midY, accuracy: 1)
    XCTAssertEqual(title.alignmentRect(forFrame: title.frame).width, 168, accuracy: 0.5)
    XCTAssertEqual(controller.parameters.cornerRadius, 23.718281828)
    let swift = try SwiftExport.source(for: controller.parameters, observed: [:])
    XCTAssertTrue(swift.contains("23.718281828"))
    XCTAssertTrue(swift.contains("var secondaryEffect:"))
    XCTAssertFalse(swift.contains("correction"))
    for index in 0..<6 {
      let item = NSMenuItem()
      item.tag = index
      controller.inspectorTab(item)
      root.layoutSubtreeIfNeeded()
      for view in descendants(root) {
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
          row.arrangedSubviews.contains(where: { $0 is NSSlider })
        {
          XCTAssertEqual(check.title.first?.isUppercase, true, check.title)
          XCTAssertEqual(check.bounds.width, 168, accuracy: 0.5)
          let group = try XCTUnwrap(row.superview)
          let hint = try XCTUnwrap(descendants(group).compactMap { $0 as? NSTextField }.first {
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
          row.arrangedSubviews.contains(where: { $0 is NSSlider || $0 is NSSegmentedControl })
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
    try await Task.sleep(for: .milliseconds(150))
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let slider = try XCTUnwrap(
      descendants(controller.window.contentView!).compactMap { $0 as? NSSlider }
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
    try await Task.sleep(for: .milliseconds(150))
    controller.change {
      $0.filterInputs["inputBlurRadius"] = 7.125
      $0.haloBlurRadius = 23.5
    }
    serviceSliderTracking()
    let background = try XCTUnwrap(PrivateGlass.backgrounds(controller.canvas.container).first)
    let blur = try XCTUnwrap(
      PrivateGlass.read(background, "filters.glassBackground.inputBlurRadius") as? NSNumber)
    XCTAssertEqual(blur.doubleValue, 7.125)
    let halo = try XCTUnwrap(
      PrivateGlass.layers(controller.canvas.layer).first { layer in
        (layer.filters as? [NSObject])?.contains {
          PrivateGlass.read($0, "name") as? String == "variableBlur"
        } == true
      })
    let radius = try XCTUnwrap(
      PrivateGlass.read(halo, "filters.variableBlur.inputRadius") as? NSNumber)
    XCTAssertEqual(radius.doubleValue, 23.5)
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
      try await Task.sleep(for: .milliseconds(100))
      XCTAssertEqual(canvas.activeHaloMode, mode)
      XCTAssertTrue(canvas.issues.isEmpty, canvas.issues.joined(separator: "; "))
    }
    controller.toggleSecondary()
    try await Task.sleep(for: .milliseconds(400))
    let expanded = canvas.visibleSurfaceBounds.insetBy(
      dx: -controller.parameters.haloMargin, dy: -controller.parameters.haloMargin)
    XCTAssertTrue(
      canvas.bounds.contains(expanded),
      "Detached preview must include the full halo around expansion")
    controller.change { $0.panelGap = 40 }
    XCTAssertEqual(canvas.mainSurfaceFrame.height, controller.parameters.height + 80 + 40)
    XCTAssertTrue(canvas.issues.isEmpty, canvas.issues.joined(separator: "; "))
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
    try await Task.sleep(for: .milliseconds(180))
    XCTAssertGreaterThan(controller.canvas.mainSurfaceFrame.height, before.height)
    XCTAssertLessThan(controller.canvas.mainSurfaceFrame.height, before.height + 90)
    assertShadowAttached(controller.canvas)
    // A parameter edit during motion replaces the animated recipe and settles geometry.
    controller.change { $0.cornerRadius = 24.5 }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(controller.canvas.mainSurfaceFrame.height, before.height + 90)
    assertShadowAttached(controller.canvas)
  }

  @MainActor func testHaloMaskTracksCurveAndPanelHole() throws {
    var p = GlassParameters()
    p.haloCurve.nodes[0].outgoing = CurvePoint(x: 0.25, y: 0.25)
    p.haloCurve.nodes[1].incoming = CurvePoint(x: 0.75, y: 0.75)
    p.haloMargin = 50
    let size = CGSize(width: 700, height: 600)
    let panel = CGRect(x: 140, y: 200, width: 420, height: 200)
    func alpha(_ image: CGImage, x: Int, y: Int) throws -> Double {
      let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
      return Double(bytes[y * image.bytesPerRow + x * 4 + 3]) / 255
    }
    let start = ContinuousClock.now
    let image = try XCTUnwrap(HaloMask.make(size: size, panels: [panel], p: p, scale: 2))
    print("Halo mask generation: \(start.duration(to: .now)) for 700×600 pt at 2×")
    XCTAssertEqual(try alpha(image, x: 700, y: 600), 1, accuracy: 0.01)
    XCTAssertEqual(try alpha(image, x: 700, y: 350), 0.5, accuracy: 0.03)
    XCTAssertEqual(try alpha(image, x: 700, y: 250), 0, accuracy: 0.01)
    p.haloUnderPanels = false
    let cutout = try XCTUnwrap(HaloMask.make(size: size, panels: [panel], p: p, scale: 2))
    XCTAssertEqual(try alpha(cutout, x: 700, y: 600), 0, accuracy: 0.01)
    XCTAssertEqual(try alpha(cutout, x: 700, y: 350), 0.5, accuracy: 0.03)
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
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertEqual(
        controller.canvas.mainSurfaceFrame.origin, origin,
        "Effect \(effect) must keep the main surface anchored")
      assertShadowAttached(controller.canvas)
      controller.toggleSecondary()
      try await Task.sleep(for: .milliseconds(350))
      XCTAssertEqual(controller.canvas.mainSurfaceFrame.origin, origin)
      assertShadowAttached(controller.canvas)
    }
  }

  @MainActor private func assertShadowAttached(
    _ canvas: GlassCanvas, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let shadow = canvas.shadowBounds else {
      XCTFail("Missing shadow path", file: file, line: line)
      return
    }
    let glass = canvas.visibleSurfaceBounds
    for (a, b) in [
      (shadow.minX, glass.minX), (shadow.minY, glass.minY), (shadow.width, glass.width),
      (shadow.height, glass.height),
    ] {
      XCTAssertEqual(a, b, accuracy: 0.001, file: file, line: line)
    }
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
      let data = try XCTUnwrap(board.data(forType: .init("com.alexgorbatchev.glass-recipe")))
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
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let inspector = try XCTUnwrap(descendants(content).first { $0 is Inspector })
    let inspectorBounds = inspector.convert(inspector.bounds, to: content)
    XCTAssertEqual(controller.canvas.bounds.width, 1088 * 0.8, accuracy: 0.5)
    XCTAssertEqual(
      inspectorBounds.maxX, content.bounds.maxX - 18, accuracy: 1,
      "The columns must fill the wider window, with the inspector at its right edge")
    try await Task.sleep(for: .milliseconds(400))
    controller.canvas.refreshInternals()
    XCTAssertFalse(
      controller.canvas.observed.isEmpty, "Actual glassBackground layers must be built")
    XCTAssertTrue(
      controller.canvas.issues.isEmpty, controller.canvas.issues.joined(separator: "; "))
    XCTAssertNotNil(controller.canvas.observed["inputBlurRadius"])
    XCTAssertNotNil(controller.canvas.observedHighlights["keyAmount"])
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
      let item = NSMenuItem()
      item.tag = index
      controller.inspectorTab(item)
      controller.window.contentView?.layoutSubtreeIfNeeded()
      XCTAssertFalse(controller.window.contentView!.hasAmbiguousLayout)
      if capturing {
        try await Task.sleep(for: .milliseconds(200))
        try capture(
          controller.window, to: directory.appendingPathComponent("inspector-\(index).png"))
      }
    }
    // Change a private filter using the real layer, then remove it and require the native recipe.
    let native = try XCTUnwrap(controller.canvas.observed["inputBlurRadius"])
    controller.change { $0.filterInputs["inputBlurRadius"] = 9.125 }
    try await Task.sleep(for: .milliseconds(120))
    controller.canvas.refreshInternals()
    controller.canvas.refreshInternals()
    XCTAssertEqual(controller.canvas.observed["inputBlurRadius"], 9.125)
    controller.change { $0.filterInputs = [:] }
    try await Task.sleep(for: .milliseconds(120))
    controller.canvas.refreshInternals()
    XCTAssertEqual(controller.canvas.observed["inputBlurRadius"], native)

    let source = try SwiftExport.source(
      for: controller.parameters, observed: controller.canvas.observed)
    try source.write(
      to: directory.appendingPathComponent("DesignedGlass.swift"), atomically: true, encoding: .utf8
    )
    print(
      "Native probe: filters=\(controller.canvas.observed.count) rim=\(controller.canvas.observedHighlights.count) issues=\(controller.canvas.issues)"
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
    for variant in GlassCatalog.variants.indices {
      controller.change {
        $0.variant = variant
        $0.haloEnabled = false
      }
      try await Task.sleep(for: .milliseconds(30))
      let glass = try XCTUnwrap(
        controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
      XCTAssertEqual((PrivateGlass.read(glass, "_variant") as? NSNumber)?.intValue, variant)
    }
    controller.loadPreset(1)
    for subvariant in GlassCatalog.subvariants {
      controller.change { $0.subvariant = subvariant }
      let glass = try XCTUnwrap(
        controller.canvas.container.contentView?.subviews.first as? NSGlassEffectView)
      XCTAssertEqual(PrivateGlass.read(glass, "_subvariant") as? String, subvariant)
    }
    controller.loadPreset(0)
    try await Task.sleep(for: .milliseconds(150))
    controller.canvas.refreshInternals()
    let nativeRim = controller.canvas.observedHighlights
    controller.change { p in
      for field in GlassCatalog.filters {
        p.filterInputs[field.key] = (field.range.lowerBound + field.range.upperBound) / 2
      }
      for field in GlassCatalog.highlights { p.highlightInputs[field.key] = 0.625 }
    }
    try await Task.sleep(for: .milliseconds(150))
    controller.canvas.refreshInternals()
    controller.canvas.refreshInternals()
    for (key, value) in controller.parameters.filterInputs {
      XCTAssertEqual(try XCTUnwrap(controller.canvas.observed[key]), value, accuracy: 0.00001, key)
    }
    for (key, value) in controller.parameters.highlightInputs {
      XCTAssertEqual(
        try XCTUnwrap(controller.canvas.observedHighlights[key]), value, accuracy: 0.00001, key)
    }
    controller.change {
      $0.highlightInputs = [:]
      $0.filterInputs = [:]
    }
    try await Task.sleep(for: .milliseconds(150))
    controller.canvas.refreshInternals()
    XCTAssertEqual(controller.canvas.observedHighlights, nativeRim)
    XCTAssertTrue(
      controller.canvas.issues.isEmpty, controller.canvas.issues.joined(separator: "; "))
  }
}
