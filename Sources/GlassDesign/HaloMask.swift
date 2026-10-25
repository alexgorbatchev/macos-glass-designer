import CoreGraphics

/// Halo strength as alpha: the variableBlur filter and layer masks both read the alpha channel.
/// The mask is rebuilt on every frame of a secondary-surface animation, so it is drawn with native
/// gradients: strength depends only on distance from the group's rounded outline, which splits
/// into a solid interior, four straight edges (linear gradients), and four corners (radial).
@MainActor
enum HaloMask {
  static func make(size: CGSize, panels: [CGRect], p: GlassParameters, scale: CGFloat) -> CGImage? {
    let width = Int((size.width * scale).rounded(.up))
    let height = Int((size.height * scale).rounded(.up))
    guard width > 0, height > 0, let first = panels.first,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
    else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    // Device pixels throughout, so cell boundaries can be snapped to whole pixels.
    func pixels(_ rect: CGRect) -> CGRect {
      CGRect(
        x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale,
        height: rect.height * scale)
    }
    // The halo surrounds the group's bounding shape.
    let group = pixels(panels.dropFirst().reduce(first) { $0.union($1) })
    let radius = min(p.cornerRadius * scale, group.width / 2, group.height / 2)
    let margin = p.haloMargin * scale
    let outer = group.insetBy(dx: -margin, dy: -margin)
    // Anti-aliased outer edge; the cells below tile the inside without overlapping.
    context.addPath(
      CGPath(
        roundedRect: outer, cornerWidth: radius + margin, cornerHeight: radius + margin,
        transform: nil))
    context.clip()
    let inside = p.haloCurve.value(at: 1)
    if margin == 0 {
      context.setFillColor(gray: 1, alpha: inside)
      context.fill(outer)
    } else if let gradient = gradient(p.haloCurve, stops: Int(margin.rounded(.up)) + 1) {
      context.setShouldAntialias(false)
      // Corner arc centres, and the whole-pixel lines between the cells.
      let arcX = (group.minX + radius, group.maxX - radius)
      let arcY = (group.minY + radius, group.maxY - radius)
      let xs = [outer.minX, arcX.0.rounded(), arcX.1.rounded(), outer.maxX]
      let ys = [outer.minY, arcY.0.rounded(), arcY.1.rounded(), outer.maxY]
      for column in 0..<3 {
        for row in 0..<3 {
          let cell = CGRect(
            x: xs[column], y: ys[row], width: xs[column + 1] - xs[column],
            height: ys[row + 1] - ys[row])
          guard cell.width > 0, cell.height > 0 else { continue }
          context.saveGState()
          context.clip(to: cell)
          switch (column, row) {
          case (1, 1):
            context.setFillColor(gray: 1, alpha: inside)
            context.fill(cell)
          case (1, _):
            // Top or bottom edge: strength falls off vertically from the outline.
            let edge = row == 0 ? group.minY : group.maxY
            let outward = row == 0 ? edge - margin : edge + margin
            context.drawLinearGradient(
              gradient, start: CGPoint(x: cell.midX, y: edge),
              end: CGPoint(x: cell.midX, y: outward),
              options: .drawsBeforeStartLocation)
          case (_, 1):
            let edge = column == 0 ? group.minX : group.maxX
            let outward = column == 0 ? edge - margin : edge + margin
            context.drawLinearGradient(
              gradient, start: CGPoint(x: edge, y: cell.midY),
              end: CGPoint(x: outward, y: cell.midY),
              options: .drawsBeforeStartLocation)
          default:
            let center = CGPoint(x: column == 0 ? arcX.0 : arcX.1, y: row == 0 ? arcY.0 : arcY.1)
            context.drawRadialGradient(
              gradient, startCenter: center, startRadius: radius, endCenter: center,
              endRadius: radius + margin, options: .drawsBeforeStartLocation)
          }
          context.restoreGState()
        }
      }
      context.setShouldAntialias(true)
    } else {
      return nil
    }
    if !p.haloUnderPanels {
      context.setBlendMode(.clear)
      for panel in panels.map(pixels) {
        let corner = min(p.cornerRadius * scale, panel.width / 2, panel.height / 2)
        context.addPath(
          CGPath(roundedRect: panel, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
      }
    }
    return context.makeImage()
  }

  /// Location 0 is the outline (curve X = 1) and location 1 the outer edge (curve X = 0).
  private static func gradient(_ curve: HaloCurve, stops: Int) -> CGGradient? {
    let count = max(2, stops)
    let locations = (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
    let components = locations.flatMap { [1, CGFloat(curve.value(at: 1 - $0))] }
    return CGGradient(
      colorSpace: CGColorSpaceCreateDeviceGray(), colorComponents: components,
      locations: locations, count: count)
  }
}
