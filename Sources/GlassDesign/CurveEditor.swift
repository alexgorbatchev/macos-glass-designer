import AppKit

/// Direct manipulation of ordered cubic segments; the view's coordinates are the exported curve.
@MainActor
final class CurveEditor: NSView {
  var curve = HaloCurve() {
    didSet {
      if let selectedNode, !curve.nodes.indices.contains(selectedNode) { self.selectedNode = nil }
      selectionChanged()
    }
  }
  var onChange: ((HaloCurve) -> Void)?
  var onSelectionChange: ((String) -> Void)?
  private(set) var selectedNode: Int? = 0
  private enum Part { case point, incoming, outgoing }
  private var part: Part = .point
  var plotRect: CGRect { bounds.insetBy(dx: 25, dy: 24) }
  override var acceptsFirstResponder: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Editable blur curve")
    setAccessibilityHelp(
      "Drag points and handles. Double-click to add a point. Tab selects points. Arrow keys move the selection; Shift moves faster. Delete removes a point."
    )
    updateAccessibility()
  }
  required init?(coder: NSCoder) { nil }

  func viewPoint(_ point: CurvePoint) -> NSPoint {
    NSPoint(
      x: plotRect.minX + point.x * plotRect.width, y: plotRect.minY + point.y * plotRect.height)
  }
  private func curvePoint(_ point: NSPoint) -> CurvePoint {
    CurvePoint(
      x: (point.x - plotRect.minX) / plotRect.width, y: (point.y - plotRect.minY) / plotRect.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    let area = plotRect
    let attributes: [NSAttributedString.Key: Any] = [
      .font: DesignerFont.font(size: 9), .foregroundColor: NSColor.secondaryLabelColor,
    ]
    for index in 0...4 {
      let n = Double(index) / 4
      let x = area.minX + area.width * n
      let y = area.minY + area.height * n
      NSColor.separatorColor.setStroke()
      let grid = NSBezierPath()
      grid.move(to: NSPoint(x: x, y: area.minY))
      grid.line(to: NSPoint(x: x, y: area.maxY))
      grid.move(to: NSPoint(x: area.minX, y: y))
      grid.line(to: NSPoint(x: area.maxX, y: y))
      grid.stroke()
      let text = String(format: "%.2g", n) as NSString
      text.draw(at: NSPoint(x: x - 8, y: 5), withAttributes: attributes)
      text.draw(at: NSPoint(x: 2, y: y - 5), withAttributes: attributes)
    }
    let path = NSBezierPath()
    path.lineWidth = 2
    path.move(to: viewPoint(CurvePoint(x: 0, y: curve.value(at: 0))))
    if let first = curve.nodes.first { path.line(to: viewPoint(first.position)) }
    for (left, right) in zip(curve.nodes, curve.nodes.dropFirst()) {
      path.curve(
        to: viewPoint(right.position), controlPoint1: viewPoint(left.outgoing),
        controlPoint2: viewPoint(right.incoming))
    }
    path.line(to: viewPoint(CurvePoint(x: 1, y: curve.value(at: 1))))
    NSColor.controlAccentColor.setStroke()
    path.stroke()
    if let index = selectedNode, curve.nodes.indices.contains(index) {
      let node = curve.nodes[index]
      for (handle, visible) in [
        (node.incoming, index > 0), (node.outgoing, index < curve.nodes.count - 1),
      ] where visible {
        let point = viewPoint(handle)
        let anchor = viewPoint(node.position)
        let line = NSBezierPath()
        line.move(to: anchor)
        line.line(to: point)
        NSColor.secondaryLabelColor.setStroke()
        line.stroke()
        NSColor.controlBackgroundColor.setFill()
        let shape = NSBezierPath(
          ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        shape.fill()
        NSColor.controlAccentColor.setStroke()
        shape.stroke()
      }
    }
    for (index, node) in curve.nodes.enumerated() {
      let point = viewPoint(node.position)
      (index == selectedNode ? NSColor.controlAccentColor : NSColor.labelColor).setFill()
      NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).fill()
    }
    if window?.firstResponder === self {
      NSColor.keyboardFocusIndicatorColor.setStroke()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).stroke()
    }
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    guard plotRect.insetBy(dx: -8, dy: -8).contains(point) else { return }
    if event.clickCount == 2 {
      if let index = curve.insert(at: curvePoint(point)) {
        selectedNode = index
        part = .point
        publish()
      }
      return
    }
    func near(_ p: CurvePoint) -> Bool {
      hypot(viewPoint(p).x - point.x, viewPoint(p).y - point.y) <= 9
    }
    if let index = curve.nodes.firstIndex(where: { near($0.position) }) {
      selectedNode = index
      part = .point
      selectionChanged()
      return
    }
    if let index = selectedNode {
      if index > 0 && near(curve.nodes[index].incoming) {
        part = .incoming
        return
      }
      if index < curve.nodes.count - 1 && near(curve.nodes[index].outgoing) {
        part = .outgoing
        return
      }
    }
    selectedNode = nil
    part = .point
    selectionChanged()
  }

  override func mouseDragged(with event: NSEvent) {
    moveSelection(to: curvePoint(convert(event.locationInWindow, from: nil)))
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 51 || event.keyCode == 117 {
      removeSelection()
      return
    }
    if event.keyCode == 48 {
      let next = (selectedNode ?? -1) + (event.modifierFlags.contains(.shift) ? -1 : 1)
      if curve.nodes.indices.contains(next) {
        selectedNode = next
        part = .point
        selectionChanged()
      } else if event.modifierFlags.contains(.shift) {
        window?.selectPreviousKeyView(nil)
      } else {
        window?.selectNextKeyView(nil)
      }
      return
    }
    guard let index = selectedNode, [123, 124, 125, 126].contains(event.keyCode) else {
      super.keyDown(with: event)
      return
    }
    let node = curve.nodes[index]
    var point =
      part == .incoming ? node.incoming : part == .outgoing ? node.outgoing : node.position
    let step = event.modifierFlags.contains(.shift) ? 0.05 : 0.01
    if event.keyCode == 123 { point.x -= step }
    if event.keyCode == 124 { point.x += step }
    if event.keyCode == 125 { point.y -= step }
    if event.keyCode == 126 { point.y += step }
    moveSelection(to: point)
  }

  func removeSelection() {
    guard let index = selectedNode, curve.remove(at: index) else { return }
    selectedNode = min(index, curve.nodes.count - 1)
    part = .point
    publish()
  }
  private func moveSelection(to point: CurvePoint) {
    guard let index = selectedNode else { return }
    if part == .point {
      curve.moveNode(index, to: point)
    } else {
      curve.moveHandle(index, incoming: part == .incoming, to: point)
    }
    publish()
  }
  private func publish() {
    selectionChanged()
    onChange?(curve)
  }
  private func selectionChanged() {
    needsDisplay = true
    updateAccessibility()
    let detail =
      selectedNode.map { index in
        let node = curve.nodes[index]
        let point =
          part == .incoming ? node.incoming : part == .outgoing ? node.outgoing : node.position
        let name = part == .incoming ? "In" : part == .outgoing ? "Out" : "Point"
        return String(format: "%@ %d · X %.2f · Y %.2f", name, index + 1, point.x, point.y)
      } ?? "Select a point to edit its handles"
    onSelectionChange?("\(curve.nodes.count) points · \(detail)")
  }
  private func updateAccessibility() {
    setAccessibilityValue(
      "\(curve.nodes.count) curve points. Selected point \(selectedNode.map { String($0 + 1) } ?? "none")."
    )
  }
}
