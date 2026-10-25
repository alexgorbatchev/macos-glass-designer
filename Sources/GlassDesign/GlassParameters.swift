import Foundation

/// Platform-independent recipe. Distances are points, times seconds, colors sRGB HSBA in 0...1.
public struct GlassParameters: Codable, Equatable, Sendable {
  public var glassEnabled = true
  public var windowTitled = false
  public var variant = 1
  public var subvariant: String? = nil
  public var appearance = 0  // system, light, dark
  public var contentLensing = 0
  public var subduedState = 0
  public var scrimState = 0
  public var adaptiveAppearance = 2
  public var interactionState = 0
  public var useReducedShadowRadius = false
  public var cornerRadius = 16.0
  public var width = 420.0
  public var height = 200.0
  public var mergeSpacing = 8.0
  public var panelGap = 10.0
  public var tintHue = 0.0
  public var tintSaturation = 0.0
  public var tintBrightness = 0.0
  public var tintAlpha = 0.0
  public var fillHue = 0.0
  public var fillSaturation = 0.0
  public var fillBrightness = 0.0
  public var fillAlpha = 0.0
  public var fillInside = false
  public var dim = 0.0
  public var windowShadow = false
  public var customShadow = false
  public var shadowOpacity = 0.35
  public var shadowRadius = 24.0
  public var shadowOffsetX = 0.0
  public var shadowOffsetY = -8.0
  public var haloEnabled = false
  public var haloMode = 0  // progressive blur, masked regular glass, masked clear glass
  public var haloMargin = 64.0
  public var haloBlurRadius = 16.0
  public var haloDim = 0.0
  public var haloUnderPanels = true
  public var haloCurve = HaloCurve()
  /// Sparse overrides. Missing keys retain the current AppKit recipe, never guessed defaults.
  public var filterInputs: [String: Double] = [:]
  public var highlightInputs: [String: Double] = [:]
  public var popSeconds = 0.24
  public var popShrink = 0.08
  public var popOpacity = 0.0
  public var secondaryEffect = 4  // emerge, unfold, pop, slide, expand
  public var secondaryEasing = 1  // smooth, spring
  public var secondarySeconds = 0.17

  public init() {}

}

public struct GlassDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 3
  public private(set) var schemaVersion = Self.currentSchemaVersion
  public var parameters: GlassParameters
  public init(parameters: GlassParameters) { self.parameters = parameters }

  public func data() throws -> Data {
    try parameters.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  public static func load(_ data: Data) throws -> Self {
    /// Other schema versions have different fields; check the version before decoding them.
    struct Header: Decodable { let schemaVersion: Int }
    let decoder = JSONDecoder()
    do {
      let version = try decoder.decode(Header.self, from: data).schemaVersion
      guard version == currentSchemaVersion else {
        throw RecipeError.invalid("Unsupported schema version \(version)")
      }
      let document = try decoder.decode(Self.self, from: data)
      try document.parameters.validate()
      return document
    } catch let error as DecodingError {
      throw RecipeError.invalid(describe(error))
    }
  }

  private static func describe(_ error: DecodingError) -> String {
    func path(_ keys: [any CodingKey]) -> String {
      let joined = keys.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }
        .joined()
      return joined.isEmpty ? "the document" : String(joined.drop { $0 == "." })
    }
    switch error {
    case .keyNotFound(let key, let context):
      return "Missing field \(path(context.codingPath + [key]))"
    case .valueNotFound(_, let context):
      return "Missing value for \(path(context.codingPath))"
    case .typeMismatch(_, let context):
      return "Wrong type for \(path(context.codingPath))"
    case .dataCorrupted(let context) where context.codingPath.isEmpty:
      return "The clipboard or file is not JSON"
    case .dataCorrupted(let context):
      return "Invalid value for \(path(context.codingPath))"
    @unknown default:
      return error.localizedDescription
    }
  }
}

public enum RecipeError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): message
    }
  }
}
