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
    let source = try SwiftExport.source(for: loaded, nativeFilterInputs: [:])
    XCTAssertTrue(source.contains("0.4123456789"))
    XCTAssertTrue(source.contains("0.73123456789"))
    XCTAssertTrue(source.contains("var haloCurve: [GlassCurveNode]"))
    try assertExportCompiles(source, named: "DesignedGlass-multipoint")
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

  /// A curve with one interior point whose handles do not line up.
  private func curveWithKinkedMiddle() -> HaloCurve {
    var curve = HaloCurve()
    let index = curve.insert(at: CurvePoint(x: 0.5, y: 0.5))!
    curve.setKind(.corner, at: index)
    curve.moveHandle(index, incoming: true, to: CurvePoint(x: 0.3, y: 0.2))
    curve.moveHandle(index, incoming: false, to: CurvePoint(x: 0.7, y: 0.4))
    return curve
  }

  private func assertOnOneLine(
    _ node: CurveNode, file: StaticString = #filePath, line: UInt = #line
  ) {
    let incoming = (node.incoming.x - node.position.x, node.incoming.y - node.position.y)
    let outgoing = (node.outgoing.x - node.position.x, node.outgoing.y - node.position.y)
    XCTAssertEqual(incoming.0 * outgoing.1 - incoming.1 * outgoing.0, 0, accuracy: 1e-9, file: file, line: line)
    XCTAssertLessThan(incoming.0 * outgoing.0 + incoming.1 * outgoing.1, 0, "Handles point apart", file: file, line: line)
  }

  private func length(_ handle: CurvePoint, _ node: CurveNode) -> Double {
    hypot(handle.x - node.position.x, handle.y - node.position.y)
  }

  func testSmoothPointsKeepHandlesOnOneLineAndKeepTheirOwnLengths() throws {
    var curve = curveWithKinkedMiddle()
    let before = curve.nodes[1]
    curve.setKind(.smooth, at: 1)
    assertOnOneLine(curve.nodes[1])
    XCTAssertEqual(curve.nodes[1].position, before.position, "Converting never moves the point")
    let inLength = length(curve.nodes[1].incoming, curve.nodes[1])
    curve.moveHandle(1, incoming: false, to: CurvePoint(x: 0.6, y: 0.7))
    XCTAssertEqual(curve.nodes[1].outgoing, CurvePoint(x: 0.6, y: 0.7))
    assertOnOneLine(curve.nodes[1])
    XCTAssertEqual(length(curve.nodes[1].incoming, curve.nodes[1]), inLength, accuracy: 1e-9)
    // Dragging the other handle rotates the first one too.
    curve.moveHandle(1, incoming: true, to: CurvePoint(x: 0.45, y: 0.3))
    XCTAssertEqual(curve.nodes[1].incoming, CurvePoint(x: 0.45, y: 0.3))
    assertOnOneLine(curve.nodes[1])
    try curve.validate()
  }

  func testSymmetricPointsMirrorHandleLength() throws {
    var curve = curveWithKinkedMiddle()
    curve.setKind(.symmetric, at: 1)
    assertOnOneLine(curve.nodes[1])
    curve.moveHandle(1, incoming: false, to: CurvePoint(x: 0.6, y: 0.6))
    assertOnOneLine(curve.nodes[1])
    XCTAssertEqual(
      length(curve.nodes[1].incoming, curve.nodes[1]), length(curve.nodes[1].outgoing, curve.nodes[1]),
      accuracy: 1e-9)
    XCTAssertEqual(curve.nodes[1].incoming.x, 0.4, accuracy: 1e-9)
    XCTAssertEqual(curve.nodes[1].incoming.y, 0.4, accuracy: 1e-9)
    try curve.validate()
  }

  func testConstrainedHandlesShortenInsteadOfLeavingTheirSegmentOrTheUnitSquare() throws {
    var curve = curveWithKinkedMiddle()
    curve.setKind(.symmetric, at: 1)
    curve.moveNode(1, to: CurvePoint(x: 0.5, y: 0.9))
    // The outgoing handle points steeply down; its mirror would leave the square above y = 1.
    curve.moveHandle(1, incoming: false, to: CurvePoint(x: 0.55, y: 0.5))
    let node = curve.nodes[1]
    assertOnOneLine(node)
    XCTAssertLessThanOrEqual(node.incoming.y, 1)
    XCTAssertEqual(length(node.incoming, node), length(node.outgoing, node), accuracy: 1e-9)
    XCTAssertEqual(node.incoming.y, 1, accuracy: 1e-9, "The mirrored handle stops at the edge")
    // Moving a neighbour narrows the segment; the smooth handles stay valid and aligned.
    curve.moveNode(0, to: CurvePoint(x: 0.48, y: 0))
    assertOnOneLine(curve.nodes[1])
    try curve.validate()
  }

  func testCornerHandlesMoveIndependently() {
    var curve = curveWithKinkedMiddle()
    let incoming = curve.nodes[1].incoming
    curve.moveHandle(1, incoming: false, to: CurvePoint(x: 0.6, y: 0.9))
    XCTAssertEqual(curve.nodes[1].incoming, incoming)
    XCTAssertEqual(curve.nodes[1].kind, .corner)
  }

  func testInsertedPointsAreSmoothAndEndpointsStayCorners() throws {
    var curve = HaloCurve()
    XCTAssertEqual(curve.nodes.map(\.kind), [.corner, .corner])
    let middle = try XCTUnwrap(curve.insert(at: CurvePoint(x: 0.5, y: 0.8)))
    XCTAssertEqual(curve.nodes[middle].kind, .smooth)
    assertOnOneLine(curve.nodes[middle])
    curve.setKind(.smooth, at: 0)
    XCTAssertEqual(curve.nodes[0].kind, .corner, "Endpoints have one handle")
    XCTAssertTrue(curve.remove(at: 0))
    XCTAssertEqual(curve.nodes[0].kind, .corner, "A point that becomes an endpoint is a corner")
    XCTAssertEqual(curve.nodes[0].incoming, curve.nodes[0].position, "Endpoints have no outer handle")
    try curve.validate()
  }

  func testSplittingBesideASymmetricPointKeepsTheShapeAndMakesItSmooth() throws {
    var curve = curveWithKinkedMiddle()
    curve.setKind(.symmetric, at: 1)
    let shape = (0...20).map { curve.value(at: Double($0) / 20) }
    let index = try XCTUnwrap(curve.insert(at: CurvePoint(x: 0.75, y: curve.value(at: 0.75))))
    XCTAssertEqual(index, 2)
    for (i, value) in shape.enumerated() {
      XCTAssertEqual(curve.value(at: Double(i) / 20), value, accuracy: 0.00001)
    }
    XCTAssertEqual(curve.nodes[1].kind, .smooth, "Its split handle is shorter than its other one")
    assertOnOneLine(curve.nodes[1])
    try curve.validate()
  }

  func testValidationRejectsInconsistentPointKinds() {
    var curve = curveWithKinkedMiddle()
    curve.nodes[1].kind = .smooth
    XCTAssertThrowsError(try curve.validate())
    curve = HaloCurve()
    curve.nodes[0].kind = .smooth
    XCTAssertThrowsError(try curve.validate())
  }

  func testPointKindsRoundTripInSchemaThreeAndExport() throws {
    var p = GlassParameters()
    let index = try XCTUnwrap(p.haloCurve.insert(at: CurvePoint(x: 0.5, y: 0.5)))
    p.haloCurve.setKind(.symmetric, at: index)
    let data = try GlassDocument(parameters: p).data()
    XCTAssertEqual(try GlassDocument.load(data).parameters, p)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["schemaVersion"] as? Int, 3)
    var older = json
    older["schemaVersion"] = 2
    XCTAssertThrowsError(try GlassDocument.load(JSONSerialization.data(withJSONObject: older))) {
      XCTAssertEqual($0.localizedDescription, "Unsupported schema version 2")
    }
    let source = try SwiftExport.source(for: p, nativeFilterInputs: [:])
    XCTAssertTrue(source.contains("kind: .symmetric"), source)
    try assertExportCompiles(source, named: "DesignedGlass-point-kinds")
  }
}
