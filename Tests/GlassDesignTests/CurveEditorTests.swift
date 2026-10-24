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
    let tab = NSMenuItem()
    tab.tag = 1
    controller.inspectorTab(tab)
    let root = try XCTUnwrap(controller.window.contentView)
    root.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let editor = try XCTUnwrap(descendants(root).compactMap { $0 as? CurveEditor }.first)
    XCTAssertGreaterThanOrEqual(editor.bounds.height, 300)
    let sliders = descendants(root).compactMap { $0 as? NSSlider }
    XCTAssertEqual(sliders.count, 3, "Only halo margin, radius, and dimming retain sliders")
    func event(_ type: NSEvent.EventType, _ point: CurvePoint, clicks: Int = 1) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type,
          location: editor.convert(editor.viewPoint(point), to: nil), modifierFlags: [],
          timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
          eventNumber: 0, clickCount: clicks, pressure: 1))
    }
    func maskBytes() throws -> Data {
      let layer = try XCTUnwrap(
        PrivateGlass.layers(controller.canvas.layer).first {
          guard let contents = $0.mask?.contents else { return false }
          return CFGetTypeID(contents as CFTypeRef) == CGImage.typeID
        })
      let image = try XCTUnwrap(layer.mask?.contents) as! CGImage
      return try XCTUnwrap(image.dataProvider?.data) as Data
    }
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
}
