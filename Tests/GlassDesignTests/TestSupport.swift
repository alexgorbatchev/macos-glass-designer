import AppKit
import XCTest

@testable import GlassDesign

@MainActor
func descendants(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap { descendants(of: $0) }
}

@MainActor
extension DesignerController {
  func selectInspector(_ index: Int) {
    let item = NSMenuItem()
    item.tag = index
    inspectorTab(item)
  }
}

struct WaitTimeout: LocalizedError {
  let condition: String
  let detail: String
  var errorDescription: String? {
    "Timed out waiting for \(condition)" + (detail.isEmpty ? "" : ": \(detail)")
  }
}

/// Native readouts and animations finish on the main run loop; poll instead of guessing a delay.
@MainActor
func waitUntil(
  _ condition: String, timeout: Duration = .seconds(5), detail: () -> String = { "" },
  _ satisfied: () throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while try !satisfied() {
    guard ContinuousClock.now < deadline else {
      throw WaitTimeout(condition: condition, detail: detail())
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

/// Reads the live private value from AppKit's layers, not the designer's readout.
/// `nil` until AppKit has built the layers for the current recipe.
@MainActor
func liveFilterInput(_ canvas: GlassCanvas, _ key: String) -> Double? {
  var issues: [String] = []
  guard let background = PrivateGlass.backgrounds(canvas.container, issues: &issues).first else {
    return nil
  }
  let value = PrivateGlass.read(background, "filters.glassBackground.\(key)", issues: &issues)
  return (value as? NSNumber)?.doubleValue
}

@MainActor
func liveHighlightInput(_ canvas: GlassCanvas, _ key: String) -> Double? {
  var issues: [String] = []
  guard let effect = PrivateGlass.highlights(canvas.container, issues: &issues).first?.1 else {
    return nil
  }
  return (PrivateGlass.read(effect, key, issues: &issues) as? NSNumber)?.doubleValue
}

/// The custom shadow path outlines exactly the visible glass surfaces.
@MainActor
func shadowIsAttached(_ canvas: GlassCanvas) -> Bool {
  guard let shadow = canvas.shadowBounds else { return false }
  let glass = canvas.visibleSurfaceBounds
  return [
    (shadow.minX, glass.minX), (shadow.minY, glass.minY), (shadow.width, glass.width),
    (shadow.height, glass.height),
  ].allSatisfy { abs($0 - $1) < 0.001 }
}

/// The Swift export must compile on its own, with no import of this project.
func assertExportCompiles(
  _ source: String, named name: String, file: StaticString = #filePath, line: UInt = #line
) throws {
  let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(".tmp/verification")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appendingPathComponent("\(name).swift")
  try source.write(to: url, atomically: true, encoding: .utf8)
  let process = Process()
  let errors = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = ["swiftc", "-warnings-as-errors", "-typecheck", url.path]
  process.standardError = errors
  try process.run()
  let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  process.waitUntilExit()
  XCTAssertEqual(process.terminationStatus, 0, output, file: file, line: line)
}
