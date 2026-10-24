import XCTest

@testable import GlassDesign

final class RecipeTests: XCTestCase {
  func testDocumentRoundTripPreservesFractionalParametersAndSparseOverrides() throws {
    var p = GlassParameters()
    p.cornerRadius = 19.375
    p.tintHue = 0.79
    p.tintSaturation = 0.43
    p.tintAlpha = 0.123456789
    p.filterInputs = ["inputBlurRadius": 9.125, "inputBleedOpacity": 0.38]
    p.highlightInputs = ["keyAmount": 1.125]
    p.subvariant = "menu"
    XCTAssertEqual(try GlassDocument.load(GlassDocument(parameters: p).data()).parameters, p)
  }

  func testInvalidPrivateEnumsAndUnknownFilterKeysAreRejectedBeforeAppKit() {
    for value in [-1, 3, 42] {
      var p = GlassParameters()
      p.interactionState = value
      XCTAssertThrowsError(try p.validate())
      p.interactionState = 0
      p.adaptiveAppearance = value
      XCTAssertThrowsError(try p.validate())
    }
    var p = GlassParameters()
    p.filterInputs["inventedInput"] = 1
    XCTAssertThrowsError(try p.validate())
  }

  func testInvalidGeometryAndUnorderedBezierEndpointsAreRejected() {
    var p = GlassParameters()
    p.width = .nan
    XCTAssertThrowsError(try p.validate())
    p.width = 420
    p.haloCurve.nodes[0].position.x = 0.9
    p.haloCurve.nodes[1].position.x = 0.2
    XCTAssertThrowsError(try p.validate())
  }

  func testHaloBezierPreservesEndpointStrengthAndIsBounded() {
    var p = GlassParameters()
    p.haloCurve.moveNode(0, to: CurvePoint(x: 0.2, y: 0.3))
    p.haloCurve.moveNode(1, to: CurvePoint(x: 0.8, y: 0.9))
    p.haloCurve.nodes[0].outgoing.y = 0.4
    p.haloCurve.nodes[1].incoming.y = 0.7
    XCTAssertEqual(p.haloStrength(at: 0), 0.3)
    XCTAssertEqual(p.haloStrength(at: 1), 0.9)
    XCTAssertGreaterThan(p.haloStrength(at: 0.5), 0.3)
    XCTAssertLessThan(p.haloStrength(at: 0.5), 0.9)
  }

  func testSwiftExportContainsEveryParameterWithoutRounding() throws {
    var p = GlassParameters()
    p.cornerRadius = 19.375
    p.tintHue = 0.718281828
    p.subvariant = "menu"
    p.filterInputs = ["inputBlurRadius": 6.125]
    let source = try SwiftExport.source(for: p, observed: ["inputBlurRadius": 6.125])
    for child in Mirror(reflecting: p).children {
      XCTAssertTrue(source.contains("var \(child.label!):"), child.label!)
    }
    XCTAssertTrue(source.contains("19.375"))
    XCTAssertTrue(source.contains("0.718281828"))
    XCTAssertTrue(source.contains("inputBlurRadius"))
    XCTAssertTrue(source.contains("NSGlassEffectView"))
    XCTAssertTrue(source.contains("glassBackground"))
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".tmp/verification")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try source.write(
      to: directory.appendingPathComponent("DesignedGlass-with-overrides.swift"), atomically: true,
      encoding: .utf8)
  }
}
