import XCTest

@testable import GlassDesign

final class CurveTests: XCTestCase {
  func testAddingPointSplitsBezierWithoutChangingBlurThenAllowsEditingAndRemoval() throws {
    var curve = HaloCurve()
    let before = (0...100).map { curve.value(at: Double($0) / 100) }
    let index = try XCTUnwrap(curve.insert(at: CurvePoint(x: 0.4, y: curve.value(at: 0.4))))
    XCTAssertEqual(curve.nodes.count, 3)
    for i in 0...100 {
      XCTAssertEqual(curve.value(at: Double(i) / 100), before[i], accuracy: 0.00001)
    }
    curve.moveNode(index, to: CurvePoint(x: 0.45, y: 0.85))
    XCTAssertEqual(curve.value(at: 0.45), 0.85, accuracy: 0.00001)
    curve.moveHandle(index, incoming: true, to: CurvePoint(x: -1, y: 2))
    XCTAssertEqual(curve.nodes[index].incoming.x, curve.nodes[index - 1].position.x)
    XCTAssertEqual(curve.nodes[index].incoming.y, 1)
    try curve.validate()
    XCTAssertTrue(curve.remove(at: index))
    XCTAssertEqual(curve.nodes.count, 2)
    XCTAssertFalse(curve.remove(at: 0))
  }

  func testArbitraryPointsRoundTripAndExportWithoutLosingCoordinates() throws {
    var p = GlassParameters()
    for x in [0.2, 0.4, 0.6, 0.8] {
      _ = p.haloCurve.insert(at: CurvePoint(x: x, y: x))
    }
    p.haloCurve.moveNode(2, to: CurvePoint(x: 0.4123456789, y: 0.73123456789))
    let loaded = try GlassDocument.load(GlassDocument(parameters: p).data()).parameters
    XCTAssertEqual(loaded, p)
    XCTAssertEqual(loaded.haloCurve.nodes.count, 6)
    let source = try SwiftExport.source(for: loaded, observed: [:])
    XCTAssertTrue(source.contains("0.4123456789"))
    XCTAssertTrue(source.contains("0.73123456789"))
    XCTAssertTrue(source.contains("var haloCurve: [GlassCurveNode]"))
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".tmp/verification")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try source.write(
      to: directory.appendingPathComponent("DesignedGlass-multipoint.swift"), atomically: true,
      encoding: .utf8)
  }

  func testCurveRejectsCrossedNodesAndRetainsEndpointStrengthOutsideTheirPositions() throws {
    var curve = HaloCurve()
    curve.moveNode(0, to: CurvePoint(x: 0.2, y: 0.3))
    curve.moveNode(1, to: CurvePoint(x: 0.8, y: 0.9))
    XCTAssertEqual(curve.value(at: 0), 0.3)
    XCTAssertEqual(curve.value(at: 1), 0.9)
    try curve.validate()
    curve.nodes[1].position.x = 0.1
    XCTAssertThrowsError(try curve.validate())
    curve.nodes[1].position.x = .nan
    XCTAssertThrowsError(try curve.validate())
  }
}
