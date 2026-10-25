import AppKit
import XCTest

@testable import GlassDesign

final class CurveEditorTests: XCTestCase {
  @MainActor func testPointerAndKeyboardEditArbitraryPointsAndUpdateTheRecipeAndMask() async throws
  {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.loadPreset(2)
    controller.selectInspector(1)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    let editor = try XCTUnwrap(descendants(of: root).compactMap { $0 as? CurveEditor }.first)
    XCTAssertGreaterThanOrEqual(editor.bounds.height, 300)
    let sliders = descendants(of: root).compactMap { $0 as? NSSlider }
    XCTAssertEqual(sliders.count, 3, "Only halo margin, radius, and dimming retain sliders")
    func event(_ type: NSEvent.EventType, _ point: CurvePoint, clicks: Int = 1) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type,
          location: editor.convert(editor.viewPoint(point), to: nil), modifierFlags: [],
          timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
          eventNumber: 0, clickCount: clicks, pressure: 1))
    }
    func maskImage() -> CGImage? {
      PrivateGlass.layers(controller.canvas.layer).lazy.compactMap { layer -> CGImage? in
        guard let contents = layer.mask?.contents,
          CFGetTypeID(contents as CFTypeRef) == CGImage.typeID
        else { return nil }
        return (contents as! CGImage)
      }.first
    }
    func maskBytes() throws -> Data {
      try XCTUnwrap(try XCTUnwrap(maskImage()).dataProvider?.data) as Data
    }
    try await waitUntil("the halo mask on its layer") { maskImage() != nil }
    let originalMask = try maskBytes()
    editor.mouseDown(with: try event(.leftMouseDown, CurvePoint(x: 0.4, y: 0.8), clicks: 2))
    XCTAssertEqual(controller.parameters.haloCurve.nodes.count, 3)
    XCTAssertEqual(editor.selectedNode, 1)
    XCTAssertTrue(controller.window.firstResponder === editor)
    XCTAssertNotEqual(try maskBytes(), originalMask)
    editor.mouseDragged(with: try event(.leftMouseDragged, CurvePoint(x: 0.45, y: 0.7)))
    XCTAssertEqual(controller.parameters.haloCurve.nodes[1].position.x, 0.45, accuracy: 0.00001)
    XCTAssertEqual(controller.parameters.haloCurve.nodes[1].position.y, 0.7, accuracy: 0.00001)
    let handle = editor.curve.nodes[1].outgoing
    editor.mouseDown(with: try event(.leftMouseDown, handle))
    editor.mouseDragged(with: try event(.leftMouseDragged, CurvePoint(x: 0.6, y: 0.2)))
    XCTAssertEqual(controller.parameters.haloCurve.nodes[1].outgoing.y, 0.2, accuracy: 0.00001)
    editor.mouseDown(with: try event(.leftMouseDown, editor.curve.nodes[1].position))
    let right = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
        characters: "\u{f703}", charactersIgnoringModifiers: "\u{f703}", isARepeat: false,
        keyCode: 124))
    editor.keyDown(with: right)
    XCTAssertEqual(controller.parameters.haloCurve.nodes[1].position.x, 0.46, accuracy: 0.00001)
    let delete = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
        characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
    editor.keyDown(with: delete)
    XCTAssertEqual(controller.parameters.haloCurve.nodes.count, 2)
    XCTAssertNoThrow(try controller.parameters.validate())
  }

  /// The Blur inspector with its curve editor, toolbar, and a helper for synthetic events.
  @MainActor private struct Harness {
    let controller: DesignerController
    let editor: CurveEditor
    let root: NSView

    init() throws {
      _ = NSApplication.shared
      controller = DesignerController()
      controller.window.orderFront(nil)
      controller.loadPreset(2)
      controller.selectInspector(1)
      root = try XCTUnwrap(controller.window.contentView)
      root.layoutSubtreeIfNeeded()
      editor = try XCTUnwrap(descendants(of: root).compactMap { $0 as? CurveEditor }.first)
    }

    var curve: HaloCurve { controller.parameters.haloCurve }

    func button(_ title: String) throws -> NSButton {
      try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSButton }.first { $0.title == title })
    }

    func kinds() throws -> NSSegmentedControl {
      try XCTUnwrap(descendants(of: root).compactMap { $0 as? NSSegmentedControl }.first {
        $0.segmentCount == 3 && $0.label(forSegment: 0) == "Corner"
      })
    }

    func mouse(
      _ type: NSEvent.EventType, _ point: CurvePoint, clicks: Int = 1,
      modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: editor.convert(editor.viewPoint(point), to: nil),
          modifierFlags: modifiers, timestamp: 0, windowNumber: controller.window.windowNumber,
          context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
    }

    func key(_ characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
          windowNumber: controller.window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0))
    }

    func samples() -> [Double] { (0...20).map { curve.value(at: Double($0) / 20) } }
  }

  @MainActor func testToolbarAddsDeletesAndConvertsPoints() throws {
    let harness = try Harness()
    defer { harness.controller.window.orderOut(nil) }
    let add = try harness.button("Add point")
    let delete = try harness.button("Delete point")
    let kinds = try harness.kinds()
    XCTAssertFalse(kinds.isEnabled, "Endpoints are always corners")
    XCTAssertFalse(delete.isEnabled, "A curve keeps at least two points")
    let shape = harness.samples()
    add.performClick(nil)
    XCTAssertEqual(harness.curve.nodes.count, 3)
    XCTAssertEqual(harness.editor.selectedNode, 1)
    for (before, after) in zip(shape, harness.samples()) {
      XCTAssertEqual(before, after, accuracy: 0.00001, "Adding a point keeps the curve")
    }
    XCTAssertTrue(kinds.isEnabled)
    XCTAssertTrue(delete.isEnabled)
    XCTAssertEqual(kinds.selectedSegment, 1, "New points are smooth")
    kinds.selectedSegment = 0
    XCTAssertTrue(kinds.sendAction(kinds.action, to: kinds.target))
    XCTAssertEqual(harness.curve.nodes[1].kind, .corner)
    kinds.selectedSegment = 2
    XCTAssertTrue(kinds.sendAction(kinds.action, to: kinds.target))
    XCTAssertEqual(harness.curve.nodes[1].kind, .symmetric)
    delete.performClick(nil)
    XCTAssertEqual(harness.curve.nodes.count, 2)
    XCTAssertFalse(delete.isEnabled)
  }

  @MainActor func testOptionClickAndContextMenusEditPoints() throws {
    let harness = try Harness()
    defer { harness.controller.window.orderOut(nil) }
    let editor = harness.editor
    editor.mouseDown(with: try harness.mouse(.leftMouseDown, CurvePoint(x: 0.4, y: 0.8), clicks: 2))
    let point = harness.curve.nodes[1].position
    XCTAssertEqual(harness.curve.nodes[1].kind, .smooth)
    editor.mouseDown(with: try harness.mouse(.leftMouseDown, point, modifiers: .option))
    XCTAssertEqual(harness.curve.nodes[1].kind, .corner, "Option-click makes a smooth point sharp")
    editor.mouseDown(with: try harness.mouse(.leftMouseDown, point, modifiers: .option))
    XCTAssertEqual(harness.curve.nodes[1].kind, .smooth)

    let pointMenu = try XCTUnwrap(editor.menu(for: try harness.mouse(.rightMouseDown, point)))
    XCTAssertEqual(
      pointMenu.items.map(\.title), ["Corner", "Smooth", "Symmetric", "", "Delete Point"])
    XCTAssertEqual(pointMenu.items[1].state, .on)
    pointMenu.performActionForItem(at: 2)
    XCTAssertEqual(harness.curve.nodes[1].kind, .symmetric)

    let shape = harness.samples()
    let curveMenu = try XCTUnwrap(
      editor.menu(for: try harness.mouse(.rightMouseDown, CurvePoint(x: 0.75, y: 0.1))))
    XCTAssertEqual(curveMenu.items.map(\.title), ["Add Point Here"])
    curveMenu.performActionForItem(at: 0)
    XCTAssertEqual(harness.curve.nodes.count, 4)
    XCTAssertEqual(harness.curve.nodes[2].position.x, 0.75, accuracy: 0.01)
    for (before, after) in zip(shape, harness.samples()) {
      XCTAssertEqual(before, after, accuracy: 0.00001, "Add Point Here keeps the curve")
    }

    let deleteMenu = try XCTUnwrap(
      editor.menu(for: try harness.mouse(.rightMouseDown, harness.curve.nodes[2].position)))
    deleteMenu.performActionForItem(at: 4)
    XCTAssertEqual(harness.curve.nodes.count, 3)
    let endpointMenu = try XCTUnwrap(
      editor.menu(for: try harness.mouse(.rightMouseDown, harness.curve.nodes[0].position)))
    XCTAssertEqual(endpointMenu.items[0].state, .on)
    XCTAssertFalse(endpointMenu.items[1].isEnabled, "Endpoints are always corners")
  }

  @MainActor func testKeyboardUsesStandardEditingCommands() throws {
    let harness = try Harness()
    defer { harness.controller.window.orderOut(nil) }
    let editor = harness.editor
    editor.mouseDown(with: try harness.mouse(.leftMouseDown, CurvePoint(x: 0.4, y: 0.8), clicks: 2))
    editor.keyDown(with: try harness.key("\u{f703}", modifiers: .shift))
    XCTAssertEqual(harness.curve.nodes[1].position.x, 0.45, accuracy: 0.00001, "Shift moves faster")
    editor.keyDown(with: try harness.key("\u{f701}"))
    XCTAssertEqual(harness.curve.nodes[1].position.y, 0.79, accuracy: 0.00001)
    editor.keyDown(with: try harness.key("\t"))
    XCTAssertEqual(editor.selectedNode, 2)
    editor.keyDown(with: try harness.key("\u{19}", modifiers: .shift))
    XCTAssertEqual(editor.selectedNode, 1)
    editor.keyDown(with: try harness.key("\u{f728}"))
    XCTAssertEqual(harness.curve.nodes.count, 2, "Forward delete removes the point")
  }
}
