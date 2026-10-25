import AppKit
import XCTest

@testable import GlassDesign

final class StageDragTests: XCTestCase {
  @MainActor private func mouse(
    _ type: NSEvent.EventType, at point: CGPoint, in canvas: GlassCanvas
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1))
  }

  /// Presses at `start`, drags by `delta`, and releases.
  @MainActor private func drag(
    _ canvas: GlassCanvas, from start: CGPoint, by delta: CGVector
  ) throws {
    let end = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
    let target = try XCTUnwrap(canvas.window?.contentView?.hitTest(
      canvas.superview!.convert(start, from: canvas)))
    target.mouseDown(with: try mouse(.leftMouseDown, at: start, in: canvas))
    target.mouseDragged(
      with: try mouse(
        .leftMouseDragged, at: CGPoint(x: start.x + delta.dx / 2, y: start.y + delta.dy / 2),
        in: canvas))
    target.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: canvas))
    target.mouseUp(with: try mouse(.leftMouseUp, at: end, in: canvas))
  }

  @MainActor func testDraggingTheEmbeddedGlassMovesItOverTheSceneWithItsShadowAndHalo() async throws
  {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.change {
      $0.customShadow = true
      $0.haloEnabled = true
    }
    let canvas = controller.canvas
    controller.window.contentView?.layoutSubtreeIfNeeded()
    let start = canvas.mainSurfaceFrame
    // The press lands on the sample text inside the glass, which must not swallow it.
    let text = CGPoint(x: start.midX, y: start.midY + 20)
    XCTAssertTrue(
      controller.window.contentView?.hitTest(canvas.superview!.convert(text, from: canvas))
        === canvas, "Presses on the embedded glass belong to the canvas")
    let mask = canvas.haloMaskImage
    try drag(canvas, from: text, by: CGVector(dx: 120, dy: -70))
    XCTAssertEqual(canvas.mainSurfaceFrame.origin.x, start.origin.x + 120)
    XCTAssertEqual(canvas.mainSurfaceFrame.origin.y, start.origin.y - 70)
    XCTAssertTrue(shadowIsAttached(canvas), "The custom shadow follows the glass")
    XCTAssertNotIdentical(canvas.haloMaskImage, mask, "The halo is redrawn around the glass")

    // The position is the preview's, not the recipe's; edits keep it.
    XCTAssertEqual(controller.parameters, {
      var p = GlassParameters()
      p.customShadow = true
      p.haloEnabled = true
      return p
    }())
    controller.change { $0.cornerRadius = 30 }
    XCTAssertEqual(canvas.mainSurfaceFrame.origin.x, start.origin.x + 120)

    // The glass stays inside the stage, including after it grows.
    try drag(
      canvas, from: CGPoint(x: canvas.mainSurfaceFrame.midX, y: canvas.mainSurfaceFrame.midY),
      by: CGVector(dx: 5000, dy: -5000))
    XCTAssertTrue(canvas.bounds.contains(canvas.mainSurfaceFrame), "\(canvas.mainSurfaceFrame)")
    XCTAssertEqual(canvas.mainSurfaceFrame.maxX, canvas.bounds.maxX)
    XCTAssertEqual(canvas.mainSurfaceFrame.minY, canvas.bounds.minY)
    controller.change { $0.width = 800 }
    XCTAssertTrue(canvas.bounds.contains(canvas.mainSurfaceFrame), "\(canvas.mainSurfaceFrame)")

    // The second surface opens above the moved glass, still inside the stage.
    controller.change { $0.secondaryEffect = 3 }
    controller.toggleSecondary()
    try await waitUntil("the second surface to settle") {
      !canvas.secondaryAnimating
    }
    XCTAssertTrue(canvas.bounds.contains(canvas.visibleSurfaceBounds))
    XCTAssertTrue(shadowIsAttached(canvas))
  }

  @MainActor func testSecondSurfaceAtTheTopEdgePushesTheGlassDownWhileItIsOpen() async throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.change { $0.secondaryEffect = 3 }
    controller.window.contentView?.layoutSubtreeIfNeeded()
    let canvas = controller.canvas
    let start = canvas.mainSurfaceFrame
    try drag(canvas, from: CGPoint(x: start.midX, y: start.midY), by: CGVector(dx: 0, dy: 5000))
    let top = canvas.mainSurfaceFrame
    XCTAssertEqual(top.maxY, canvas.bounds.maxY)
    for showing in [true, false] {
      controller.toggleSecondary()
      try await waitUntil("the second surface to settle") { !canvas.secondaryAnimating }
      XCTAssertTrue(canvas.bounds.contains(canvas.visibleSurfaceBounds))
      XCTAssertEqual(
        canvas.mainSurfaceFrame.maxY, showing ? top.maxY - 80 - controller.parameters.panelGap : top.maxY)
    }
  }

  @MainActor func testPressingBesideTheGlassDoesNotMoveIt() throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.window.orderFront(nil)
    controller.window.contentView?.layoutSubtreeIfNeeded()
    let canvas = controller.canvas
    let start = canvas.mainSurfaceFrame
    try drag(canvas, from: CGPoint(x: 10, y: 10), by: CGVector(dx: 80, dy: 80))
    XCTAssertEqual(canvas.mainSurfaceFrame, start)
  }

  @MainActor func testDetachedPreviewKeepsItsGlassCentredForWindowDragging() throws {
    _ = NSApplication.shared
    let controller = DesignerController()
    defer {
      controller.window.orderOut(nil)
      controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    }
    controller.detachPreview()
    let preview = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Glass desktop preview" && $0.isVisible })
    let canvas = try XCTUnwrap(preview.contentView as? GlassCanvas)
    canvas.layoutSubtreeIfNeeded()
    let start = canvas.mainSurfaceFrame
    let centre = CGPoint(x: start.midX, y: start.midY)
    XCTAssertFalse(
      canvas.hitTest(canvas.superview?.convert(centre, from: canvas) ?? centre) === canvas,
      "The detached window moves by its background instead")
    canvas.mouseDown(with: try mouse(.leftMouseDown, at: centre, in: canvas))
    canvas.mouseDragged(
      with: try mouse(.leftMouseDragged, at: CGPoint(x: centre.x + 50, y: centre.y), in: canvas))
    XCTAssertEqual(canvas.mainSurfaceFrame, start)
  }
}
