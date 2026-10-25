import AppKit
import XCTest

@testable import GlassDesign

/// Captures the README screenshot. Runs only through `just screenshot`, which sets
/// `GLASS_SCREENSHOT` to the output path; Screen Recording permission is required.
final class ScreenshotTests: XCTestCase {
  @MainActor func testReadmeScreenshot() async throws {
    guard let path = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT"] else {
      throw XCTSkip("Set GLASS_SCREENSHOT to capture the README screenshot")
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    let controller = DesignerController()
    defer { controller.window.orderOut(nil) }
    controller.show()
    NSApp.activate()
    controller.loadPreset(2)
    controller.selectInspector(1)
    let root = try XCTUnwrap(controller.window.contentView)
    let views = descendants(of: root)
    func choose(_ control: NSSegmentedControl, _ label: String) throws {
      control.selectedSegment = try XCTUnwrap(
        (0..<control.segmentCount).first { control.label(forSegment: $0) == label })
      XCTAssertTrue(control.sendAction(control.action, to: control.target))
    }
    let segmented = views.compactMap { $0 as? NSSegmentedControl }
    try choose(XCTUnwrap(segmented.first { $0.label(forSegment: 0) == "Desktop" }), "Desktop")
    try choose(
      XCTUnwrap(segmented.first { $0.label(forSegment: 0) == "Light" && $0.segmentCount == 2 }),
      "Dark")
    let wallpapers = try XCTUnwrap(views.compactMap { $0 as? NSPopUpButton }.first)
    wallpapers.selectItem(withTitle: "Sonoma")
    XCTAssertEqual(wallpapers.titleOfSelectedItem, "Sonoma")
    XCTAssertTrue(wallpapers.sendAction(wallpapers.action, to: wallpapers.target))
    let backdrop = try XCTUnwrap(views.compactMap { $0 as? BackdropView }.first)
    try await waitUntil("the wallpaper and the native glass") {
      backdrop.pendingImages == 0 && !controller.canvas.nativeFilterInputs.isEmpty
    }
    // The window server composites glass asynchronously; let it settle before capturing.
    try await Task.sleep(for: .milliseconds(500))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(controller.window.windowNumber), path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(
      process.terminationStatus, 0, "Window capture requires Screen Recording permission")
    XCTAssertEqual(controller.status.stringValue, "", "No issues in the screenshot")
  }
}
