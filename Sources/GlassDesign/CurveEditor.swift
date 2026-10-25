import AppKit

extension CurvePointKind {
  var title: String {
    switch self {
    case .corner: "Corner"
    case .smooth: "Smooth"
    case .symmetric: "Symmetric"
    }
  }
}

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
  /// Called whenever the curve or the selection changes; read the selection properties below.
  var onSelectionChange: (() -> Void)?
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
      "Drag points and handles. Double-click to add a point. Option-click a point to switch corner and smooth. Tab selects points. Arrow keys move the selection; Shift moves faster. Delete removes a point."
    )
    setAccessibilityCustomActions(
      [
        NSAccessibilityCustomAction(name: "Add point", target: self, selector: #selector(addPoint)),
        NSAccessibilityCustomAction(
          name: "Delete point", target: self, selector: #selector(deleteSelectedPoint)),
      ]
        + CurvePointKind.allCases.map {
          NSAccessibilityCustomAction(
            name: "Make \($0.title.lowercased()) point", target: self,
            selector: NSSelectorFromString("make\($0.title)Point"))
        })
    updateAccessibility()
  }
  required init?(coder: NSCoder) { nil }

  // MARK: - Selection

  var selectedKind: CurvePointKind? { selectedNode.map { curve.nodes[$0].kind } }
  /// Endpoints have one handle and are always corners.
  var canChangeKind: Bool { selectedNode.map(isInterior) ?? false }
  var canDeleteSelection: Bool { selectedNode != nil && curve.nodes.count > 2 }
  var selectionSummary: String {
    let detail =
      selectedNode.map { index in
        let node = curve.nodes[index]
        let point =
          part == .incoming ? node.incoming : part == .outgoing ? node.outgoing : node.position
        let name = part == .incoming ? "In" : part == .outgoing ? "Out" : "Point"
        return String(
          format: "%@ %d · %@ · X %.2f · Y %.2f", name, index + 1, node.kind.title, point.x, point.y
        )
      } ?? "Select a point to edit it"
    return "\(curve.nodes.count) points · \(detail)"
  }

  private func isInterior(_ index: Int) -> Bool { index > 0 && index < curve.nodes.count - 1 }

  // MARK: - Commands

  /// Adds a point halfway along the selected point's following segment (or the widest segment),
  /// on the curve so its shape is kept.
  @objc func addPoint() {
    let segment: Int
    if let selectedNode {
      segment = min(selectedNode, curve.nodes.count - 2)
    } else {
      segment =
        zip(curve.nodes, curve.nodes.dropFirst()).enumerated()
        .max {
          $0.element.1.position.x - $0.element.0.position.x
            < $1.element.1.position.x - $1.element.0.position.x
        }?.offset ?? 0
    }
    let x = (curve.nodes[segment].position.x + curve.nodes[segment + 1].position.x) / 2
    insertPoint(atX: x)
  }

  func insertPoint(atX x: Double) {
    guard let index = curve.insert(at: CurvePoint(x: x, y: curve.value(at: x))) else { return }
    select(index)
    publish()
  }

  @objc func deleteSelectedPoint() {
    guard let index = selectedNode, curve.remove(at: index) else { return }
    selectedNode = min(index, curve.nodes.count - 1)
    part = .point
    publish()
  }

  func setSelectedKind(_ kind: CurvePointKind) {
    guard let index = selectedNode, canChangeKind else { return }
    curve.setKind(kind, at: index)
    publish()
  }

  @objc private func makeCornerPoint() { setSelectedKind(.corner) }
  @objc private func makeSmoothPoint() { setSelectedKind(.smooth) }
  @objc private func makeSymmetricPoint() { setSelectedKind(.symmetric) }

  @objc private func chooseKind(_ item: NSMenuItem) {
    setSelectedKind(CurvePointKind.allCases[item.tag])
  }

  @objc private func addPointHere(_ item: NSMenuItem) {
    guard let x = item.representedObject as? Double else { return }
    insertPoint(atX: x)
  }

  private func select(_ index: Int?) {
    selectedNode = index
    part = .point
    selectionChanged()
  }

  // MARK: - Drawing

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
    // Corners are diamonds; smooth points are circles, ringed when symmetric.
    for (index, node) in curve.nodes.enumerated() {
      let point = viewPoint(node.position)
      (index == selectedNode ? NSColor.controlAccentColor : NSColor.labelColor).setFill()
      switch node.kind {
      case .corner:
        let diamond = NSBezierPath()
        diamond.move(to: NSPoint(x: point.x, y: point.y + 6))
        diamond.line(to: NSPoint(x: point.x + 6, y: point.y))
        diamond.line(to: NSPoint(x: point.x, y: point.y - 6))
        diamond.line(to: NSPoint(x: point.x - 6, y: point.y))
        diamond.close()
        diamond.fill()
      case .smooth, .symmetric:
        NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).fill()
        if node.kind == .symmetric {
          NSColor.labelColor.setStroke()
          NSBezierPath(ovalIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            .stroke()
        }
      }
    }
    if window?.firstResponder === self {
      NSColor.keyboardFocusIndicatorColor.setStroke()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).stroke()
    }
  }

  // MARK: - Pointer

  private func node(near point: NSPoint) -> Int? {
    curve.nodes.firstIndex { near($0.position, point) }
  }

  private func near(_ curvePoint: CurvePoint, _ point: NSPoint) -> Bool {
    hypot(viewPoint(curvePoint).x - point.x, viewPoint(curvePoint).y - point.y) <= 9
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    guard plotRect.insetBy(dx: -8, dy: -8).contains(point) else { return }
    if event.clickCount == 2 {
      if let index = curve.insert(at: curvePoint(point)) {
        select(index)
        publish()
      }
      return
    }
    if let index = node(near: point) {
      select(index)
      if event.modifierFlags.contains(.option) && isInterior(index) {
        setSelectedKind(curve.nodes[index].kind == .corner ? .smooth : .corner)
      }
      return
    }
    if let index = selectedNode {
      if index > 0 && near(curve.nodes[index].incoming, point) {
        part = .incoming
        return
      }
      if index < curve.nodes.count - 1 && near(curve.nodes[index].outgoing, point) {
        part = .outgoing
        return
      }
    }
    select(nil)
  }

  override func mouseDragged(with event: NSEvent) {
    moveSelection(to: curvePoint(convert(event.locationInWindow, from: nil)))
  }

  /// Point menus convert or delete the point; elsewhere on the plot the menu adds a point.
  override func menu(for event: NSEvent) -> NSMenu? {
    let point = convert(event.locationInWindow, from: nil)
    guard plotRect.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
    let menu = NSMenu()
    menu.autoenablesItems = false
    if let index = node(near: point) {
      select(index)
      for (tag, kind) in CurvePointKind.allCases.enumerated() {
        let item = NSMenuItem(
          title: kind.title, action: #selector(chooseKind(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = curve.nodes[index].kind == kind ? .on : .off
        item.isEnabled = isInterior(index)
        menu.addItem(item)
      }
      menu.addItem(.separator())
      let delete = NSMenuItem(
        title: "Delete Point", action: #selector(deleteSelectedPoint), keyEquivalent: "")
      delete.target = self
      delete.isEnabled = canDeleteSelection
      menu.addItem(delete)
    } else {
      let x = min(1, max(0, curvePoint(point).x))
      let add = NSMenuItem(
        title: "Add Point Here", action: #selector(addPointHere(_:)), keyEquivalent: "")
      add.target = self
      add.representedObject = x
      add.isEnabled = !curve.nodes.contains { abs($0.position.x - x) < 0.002 }
      menu.addItem(add)
    }
    return menu
  }

  // MARK: - Keyboard: AppKit's standard key bindings

  override func keyDown(with event: NSEvent) {
    interpretKeyEvents([event])
  }

  override func moveLeft(_ sender: Any?) { nudge(dx: -0.01, dy: 0) }
  override func moveRight(_ sender: Any?) { nudge(dx: 0.01, dy: 0) }
  override func moveUp(_ sender: Any?) { nudge(dx: 0, dy: 0.01) }
  override func moveDown(_ sender: Any?) { nudge(dx: 0, dy: -0.01) }
  override func moveLeftAndModifySelection(_ sender: Any?) { nudge(dx: -0.05, dy: 0) }
  override func moveRightAndModifySelection(_ sender: Any?) { nudge(dx: 0.05, dy: 0) }
  override func moveUpAndModifySelection(_ sender: Any?) { nudge(dx: 0, dy: 0.05) }
  override func moveDownAndModifySelection(_ sender: Any?) { nudge(dx: 0, dy: -0.05) }
  override func deleteBackward(_ sender: Any?) { deleteSelectedPoint() }
  override func deleteForward(_ sender: Any?) { deleteSelectedPoint() }

  /// Tab walks through the points, then on to the next control.
  override func insertTab(_ sender: Any?) {
    let next = (selectedNode ?? -1) + 1
    if curve.nodes.indices.contains(next) { select(next) } else { window?.selectNextKeyView(nil) }
  }

  override func insertBacktab(_ sender: Any?) {
    let previous = (selectedNode ?? curve.nodes.count) - 1
    if curve.nodes.indices.contains(previous) {
      select(previous)
    } else {
      window?.selectPreviousKeyView(nil)
    }
  }

  private func nudge(dx: Double, dy: Double) {
    guard let index = selectedNode else { return }
    let node = curve.nodes[index]
    var point =
      part == .incoming ? node.incoming : part == .outgoing ? node.outgoing : node.position
    point.x += dx
    point.y += dy
    moveSelection(to: point)
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
    onSelectionChange?()
  }

  private func updateAccessibility() {
    setAccessibilityValue(
      "\(curve.nodes.count) curve points. Selected point \(selectedNode.map { "\($0 + 1), \(curve.nodes[$0].kind.title)" } ?? "none")."
    )
  }
}
