import Foundation

extension GlassParameters {
  public func validate() throws {
    func require(_ valid: Bool, _ message: String) throws {
      if !valid { throw RecipeError.invalid(message) }
    }
    try require(GlassCatalog.variants.indices.contains(variant), "Unknown glass variant")
    try require(
      subvariant == nil || GlassCatalog.subvariants.contains(subvariant!),
      "Unknown subvariant for macOS 26")
    for (name, value, range) in [
      ("appearance", appearance, 0...2), ("contentLensing", contentLensing, 0...2),
      ("subduedState", subduedState, 0...1), ("scrimState", scrimState, 0...1),
      ("adaptiveAppearance", adaptiveAppearance, 0...2),
      ("interactionState", interactionState, 0...2),
      ("secondaryEffect", secondaryEffect, 0...4), ("secondaryEasing", secondaryEasing, 0...1),
      ("haloMode", haloMode, 0...2),
    ] {
      try require(range.contains(value), "Invalid \(name): \(value)")
    }
    for field in GlassCatalog.allNumbers {
      let value = self[keyPath: field.path]
      try require(
        value.isFinite && field.range.contains(value), "\(field.key) must be in \(field.range)")
    }
    try haloCurve.validate()
    for (values, fields) in [
      (filterInputs, GlassCatalog.filters), (highlightInputs, GlassCatalog.highlights),
    ] {
      for (key, value) in values {
        guard let field = fields.first(where: { $0.key == key }) else {
          throw RecipeError.invalid("Unknown private input: \(key)")
        }
        try require(value.isFinite && field.range.contains(value), "Invalid \(key): \(value)")
      }
    }
  }
}
