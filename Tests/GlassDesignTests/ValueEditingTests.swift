import AppKit
import XCTest

@testable import GlassDesign

/// Editing an inspector value must end the ways macOS text fields do, not only with Return.
final class ValueEditingTests: XCTestCase {
  @MainActor private struct Row {
    let controller: DesignerController
    let slider: NSSlider
    let field: NSTextField

    init() throws {
      _ = NSApplication.shared
      controller = DesignerController()
      controller.window.orderFront(nil)
      controller.change { $0.cornerRadius = 16 }
      let views = descendants(of: try XCTUnwrap(controller.window.contentView))
      slider = try XCTUnwrap(
        views.compactMap { $0 as? NSSlider }.first { $0.accessibilityLabel() == "Corner radius" })
      field = try XCTUnwrap(
        views.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Corner radius value"
        })
    }

    /// Starts editing and types `text` over the current value, without committing it.
    func type(_ text: String) throws -> NSTextView {
      XCTAssertTrue(controller.window.makeFirstResponder(field))
      let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
      editor.selectAll(nil)
      editor.insertText(text, replacementRange: editor.selectedRange())
      return editor
    }

    func mouseDown(on view: NSView) throws -> NSEvent {
      let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
      return try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
          windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1))
    }
  }

  @MainActor func testEscapeCancelsTheEdit() throws {
    let row = try Row()
    defer { row.controller.window.orderOut(nil) }
    let editor = try row.type("30")
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertNil(row.field.currentEditor(), "Escape leaves edit mode")
    XCTAssertEqual(row.controller.parameters.cornerRadius, 16, "Escape discards the typed value")
    XCTAssertEqual(row.field.stringValue, "16")
  }

  @MainActor func testMovingTheSliderCancelsTheEditAndShowsTheSliderValue() throws {
    let row = try Row()
    defer { row.controller.window.orderOut(nil) }
    _ = try row.type("30")
    row.slider.doubleValue = 40
    XCTAssertTrue(row.slider.sendAction(row.slider.action, to: row.slider.target))
    XCTAssertNil(row.field.currentEditor(), "The slider leaves edit mode")
    XCTAssertEqual(row.controller.parameters.cornerRadius, 40)
    XCTAssertEqual(row.field.stringValue, "40", "The value follows the slider")
  }

  @MainActor func testPressingTheSliderCancelsTheEditBeforeItMoves() throws {
    let row = try Row()
    defer { row.controller.window.orderOut(nil) }
    _ = try row.type("30")
    // The slider tracks until mouse-up; queue one so the press completes.
    let down = try row.mouseDown(on: row.slider)
    let up = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp, location: down.locationInWindow, modifierFlags: [], timestamp: 0,
        windowNumber: down.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 0))
    NSApp.postEvent(up, atStart: true)
    row.controller.window.sendEvent(down)
    XCTAssertNil(row.field.currentEditor(), "Pressing the slider leaves edit mode")
    XCTAssertNotEqual(row.controller.parameters.cornerRadius, 30, "The typed value is discarded")
    XCTAssertEqual(
      row.field.doubleValue, row.controller.parameters.cornerRadius, "The value shows the recipe")
  }

  @MainActor func testClickingElsewhereCommitsTheEdit() throws {
    let row = try Row()
    defer { row.controller.window.orderOut(nil) }
    _ = try row.type("30")
    let title = try XCTUnwrap(
      descendants(of: try XCTUnwrap(row.controller.window.contentView))
        .compactMap { $0 as? NSTextField }.first { $0.stringValue == "Surface & color" })
    row.controller.window.sendEvent(try row.mouseDown(on: title))
    XCTAssertNil(row.field.currentEditor(), "Clicking elsewhere leaves edit mode")
    XCTAssertEqual(
      row.controller.parameters.cornerRadius, 30, "Clicking away keeps the typed value")
  }
}
