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

  func testLoadErrorsNameTheSchemaVersionOrTheFaultyField() throws {
    func message(_ json: String) -> String? {
      do {
        _ = try GlassDocument.load(Data(json.utf8))
        return nil
      } catch { return error.localizedDescription }
    }
    // Older documents fail on the version, before their different fields are decoded.
    XCTAssertEqual(
      message(#"{"schemaVersion":1,"parameters":{"cornerRadius":12}}"#),
      "Unsupported schema version 1")
    let valid = try JSONSerialization.jsonObject(
      with: GlassDocument(parameters: GlassParameters()).data()) as! [String: Any]
    func variant(_ edit: (inout [String: Any]) -> Void) throws -> String {
      var document = valid
      edit(&document)
      return String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self)
    }
    XCTAssertEqual(
      message(try variant { document in
        var parameters = document["parameters"] as! [String: Any]
        parameters["cornerRadius"] = nil
        document["parameters"] = parameters
      }),
      "Missing field parameters.cornerRadius")
    XCTAssertEqual(
      message(try variant { document in
        var parameters = document["parameters"] as! [String: Any]
        var curve = parameters["haloCurve"] as! [String: Any]
        var nodes = curve["nodes"] as! [[String: Any]]
        nodes[1]["position"] = "middle"
        curve["nodes"] = nodes
        parameters["haloCurve"] = curve
        document["parameters"] = parameters
      }),
      "Wrong type for parameters.haloCurve.nodes[1].position")
    XCTAssertEqual(
      message(try variant { $0["schemaVersion"] = nil }), "Missing field schemaVersion")
    XCTAssertEqual(message("Copied Swift parameters"), "The clipboard or file is not JSON")
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
    p.width = 420.5
    XCTAssertThrowsError(try p.validate()) {
      XCTAssertEqual($0.localizedDescription, "width must be a whole number of points")
    }
    p.width = 420
    p.height = 200.25
    XCTAssertThrowsError(try p.validate())
    p.height = 200
    XCTAssertNoThrow(try p.validate())
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
    XCTAssertEqual(p.haloCurve.value(at: 0), 0.3)
    XCTAssertEqual(p.haloCurve.value(at: 1), 0.9)
    XCTAssertGreaterThan(p.haloCurve.value(at: 0.5), 0.3)
    XCTAssertLessThan(p.haloCurve.value(at: 0.5), 0.9)
  }

  func testSwiftExportContainsEveryParameterWithoutRounding() throws {
    var p = GlassParameters()
    p.cornerRadius = 19.375
    p.tintHue = 0.718281828
    p.subvariant = "menu"
    p.filterInputs = ["inputBlurRadius": 6.125]
    let source = try SwiftExport.source(for: p, nativeFilterInputs: ["inputBlurRadius": 6.125])
    for child in Mirror(reflecting: p).children {
      XCTAssertTrue(source.contains("var \(child.label!):"), child.label!)
    }
    XCTAssertTrue(source.contains("19.375"))
    XCTAssertTrue(source.contains("0.718281828"))
    XCTAssertTrue(source.contains("inputBlurRadius"))
    XCTAssertTrue(source.contains("NSGlassEffectView"))
    XCTAssertTrue(source.contains("glassBackground"))
    try assertExportCompiles(source, named: "DesignedGlass-with-overrides")
    try assertExportCompiles(
      try SwiftExport.source(for: GlassParameters(), nativeFilterInputs: [:]),
      named: "DesignedGlass-defaults")
  }
}
