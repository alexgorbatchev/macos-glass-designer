import AppKit

/// Xcode's "Default (Light)" and "Default (Dark)" source editor colors.
struct CodePalette {
  let background: NSColor
  let currentLine: NSColor
  private let plain: NSColor
  private let keyword: NSColor
  private let string: NSColor
  private let comment: NSColor
  private let number: NSColor
  private let type: NSColor
  private let function: NSColor
  private let attribute: NSColor

  init(dark: Bool) {
    func hex(_ value: UInt32) -> NSColor {
      NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    background = hex(dark ? 0x1F1F24 : 0xFFFFFF)
    currentLine = hex(dark ? 0x23252B : 0xE8F2FF)
    plain = dark ? NSColor.white.withAlphaComponent(0.85) : hex(0x000000)
    keyword = hex(dark ? 0xFC5FA3 : 0x9B2393)
    string = hex(dark ? 0xFC6A5D : 0xC41A16)
    comment = hex(dark ? 0x6C7986 : 0x5D6C79)
    number = hex(dark ? 0xD0BF69 : 0x1C00CF)
    type = hex(dark ? 0xD0A8FF : 0x3900A0)
    function = hex(dark ? 0xA167E6 : 0x6C36A9)
    attribute = hex(dark ? 0xBF8555 : 0x815F03)
  }

  private enum Role { case plain, keyword, string, comment, number, type, function, attribute }

  private static let keywords: Set<String> = [
    "import", "final", "class", "struct", "enum", "func", "let", "var", "if", "else", "guard",
    "return", "for", "in", "where", "private", "public", "override", "self", "super", "init",
    "true", "false", "nil", "switch", "case", "default", "static", "some", "await", "try",
  ]
  private static let token = try! NSRegularExpression(
    pattern: #"//.*$|"(?:[^"\\]|\\.)*"|@\w+|\b\d+(?:\.\d+)?\b|\b[A-Za-z_]\w*\b"#,
    options: .anchorsMatchLines)

  private func color(_ role: Role) -> NSColor {
    switch role {
    case .plain: plain
    case .keyword: keyword
    case .string: string
    case .comment: comment
    case .number: number
    case .type: type
    case .function: function
    case .attribute: attribute
    }
  }

  private func roles(in line: String) -> [(NSRange, Role)] {
    let source = line as NSString
    return Self.token.matches(in: line, range: NSRange(location: 0, length: source.length)).map {
      match in
      let token = source.substring(with: match.range)
      let next =
        match.range.upperBound < source.length
        ? source.substring(with: NSRange(location: match.range.upperBound, length: 1)) : ""
      return (match.range, Self.role(of: token, before: next))
    }
  }

  private static func role(of token: String, before next: String) -> Role {
    if token.hasPrefix("//") { return .comment }
    if token.hasPrefix("\"") { return .string }
    if token.hasPrefix("@") { return .attribute }
    if token.first?.isNumber == true { return .number }
    if keywords.contains(token) { return .keyword }
    if token.first?.isUppercase == true { return .type }
    return next == "(" ? .function : .plain
  }

  func highlighted(_ line: String, font: NSFont) -> NSAttributedString {
    let text = NSMutableAttributedString(
      string: line, attributes: [.font: font, .foregroundColor: plain])
    for (range, role) in roles(in: line) where role != .plain {
      text.addAttribute(.foregroundColor, value: color(role), range: range)
      if role == .keyword {
        text.addAttribute(
          .font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range
        )
      }
    }
    return text
  }

  /// The most common non-plain color on a line, for the minimap.
  func color(for line: String) -> NSColor {
    let counts = Dictionary(grouping: roles(in: line).filter { $0.1 != .plain }, by: \.1)
    return counts.max { $0.value.count < $1.value.count }.map { color($0.key) } ?? plain
  }
}

enum CodeSample {
  static let lines = [
    "import AppKit",
    "",
    "/// A floating toolbar rendered as one merged sheet of glass.",
    "@MainActor",
    "final class FloatingToolbar: NSView {",
    "  private let container = NSGlassEffectContainerView()",
    "  private var buttons: [NSGlassEffectView] = []",
    "  var cornerRadius = 16.0 { didSet { needsLayout = true } }",
    "",
    "  override init(frame frameRect: NSRect) {",
    "    super.init(frame: frameRect)",
    "    container.spacing = 8",
    "    addSubview(container)",
    "  }",
    "",
    "  func addButton(symbol name: String, tint: NSColor? = nil) {",
    "    let glass = NSGlassEffectView()",
    "    glass.cornerRadius = cornerRadius",
    "    glass.tintColor = tint",
    "    // Neighbouring buttons merge when they come within the container spacing.",
    "    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)",
    "    glass.contentView = NSImageView(image: image ?? NSImage())",
    "    buttons.append(glass)",
    "    container.addSubview(glass)",
    "  }",
    "",
    "  override func layout() {",
    "    super.layout()",
    "    container.frame = bounds",
    "    let width = bounds.width / CGFloat(max(buttons.count, 1))",
    "    for (index, glass) in buttons.enumerated() {",
    "      glass.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width - 6, height: 44)",
    "    }",
    "  }",
    "",
    "  func pop(duration: TimeInterval = 0.24) {",
    "    guard let layer else { return }",
    "    let scale = CABasicAnimation(keyPath: \"transform.scale\")",
    "    scale.fromValue = 0.92",
    "    scale.toValue = 1.0",
    "    scale.duration = duration",
    "    layer.add(scale, forKey: \"pop\")",
    "  }",
    "}",
  ]
}
