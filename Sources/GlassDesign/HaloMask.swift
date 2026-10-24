import AppKit

@MainActor
enum HaloMask {
  static func make(size: CGSize, panels: [CGRect], p: GlassParameters, scale: CGFloat) -> CGImage? {
    let width = Int((size.width * scale).rounded(.up))
    let height = Int((size.height * scale).rounded(.up))
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.scaleBy(x: scale, y: scale)
    context.setBlendMode(.copy)
    // The halo surrounds the group's bounding shape.
    guard let first = panels.first else { return nil }
    let group = panels.dropFirst().reduce(first) { $0.union($1) }
    let steps = max(1, Int(p.haloMargin.rounded(.up)))
    for index in 0...steps {
      let outward = p.haloMargin * (1 - Double(index) / Double(steps))
      let strength = p.haloStrength(at: Double(index) / Double(steps))
      context.setFillColor(CGColor(gray: 1, alpha: strength))
      let outer = group.insetBy(dx: -outward, dy: -outward)
      context.addPath(
        CGPath(
          roundedRect: outer, cornerWidth: p.cornerRadius + outward,
          cornerHeight: p.cornerRadius + outward, transform: nil))
      context.fillPath()
    }
    if !p.haloUnderPanels {
      context.setBlendMode(.clear)
      for panel in panels {
        context.addPath(
          CGPath(
            roundedRect: panel, cornerWidth: p.cornerRadius,
            cornerHeight: p.cornerRadius, transform: nil))
        context.fillPath()
      }
    }
    return context.makeImage()
  }
}
