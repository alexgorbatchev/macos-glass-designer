import AppKit

@MainActor
final class BackdropView: NSView {
  var mode = 0 { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    if mode == 1 || mode == 2 {
      (mode == 1 ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.07, alpha: 1)).setFill()
      bounds.fill()
    } else {
      let colors = [
        NSColor(srgbRed: 0.08, green: 0.19, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 0.19, green: 0.46, blue: 0.62, alpha: 1),
        NSColor(srgbRed: 0.73, green: 0.55, blue: 0.44, alpha: 1),
      ]
      NSGradient(colors: colors)?.draw(in: bounds, angle: -35)
      NSColor(srgbRed: 0.90, green: 0.65, blue: 0.35, alpha: 0.65).setFill()
      NSBezierPath(
        ovalIn: CGRect(
          x: bounds.width * 0.56, y: bounds.height * 0.53,
          width: bounds.width * 0.64, height: bounds.width * 0.64)
      ).fill()
      NSColor(srgbRed: 0.14, green: 0.45, blue: 0.56, alpha: 0.8).setFill()
      let wave = NSBezierPath()
      wave.move(to: .zero)
      wave.line(to: CGPoint(x: 0, y: bounds.height * 0.4))
      wave.curve(
        to: CGPoint(x: bounds.width, y: bounds.height * 0.32),
        controlPoint1: CGPoint(x: bounds.width * 0.3, y: bounds.height * 0.7),
        controlPoint2: CGPoint(x: bounds.width * 0.6, y: bounds.height * -0.1))
      wave.line(to: CGPoint(x: bounds.width, y: 0))
      wave.close()
      wave.fill()
    }
    if mode == 3 {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .left
      let attributes: [NSAttributedString.Key: Any] = [
        .font: DesignerFont.font(size: 14, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.7), .paragraphStyle: paragraph,
      ]
      for y in stride(from: 20.0, to: bounds.height, by: 32) {
        ("Aa  Glass needs a backdrop.  0123456789  Refraction • Blur • Light" as NSString)
          .draw(at: NSPoint(x: 18, y: y), withAttributes: attributes)
      }
    }
  }
}
