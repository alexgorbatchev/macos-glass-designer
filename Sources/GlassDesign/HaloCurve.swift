import Foundation

public struct CurvePoint: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
  func mixed(with other: Self, at t: Double) -> Self {
    Self(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
  }
}

/// How a point's two handles relate while editing; the handles alone define the curve's shape.
public enum CurvePointKind: String, Codable, CaseIterable, Sendable {
  /// Independent handles: the curve may turn sharply at the point.
  case corner
  /// Handles stay on one line through the point, each keeping its own length.
  case smooth
  /// Handles stay on one line with equal lengths.
  case symmetric
}

public struct CurveNode: Codable, Equatable, Sendable {
  public var position: CurvePoint
  public var incoming: CurvePoint
  public var outgoing: CurvePoint
  public var kind: CurvePointKind
  public init(
    x: Double, y: Double, incoming: CurvePoint? = nil, outgoing: CurvePoint? = nil,
    kind: CurvePointKind = .corner
  ) {
    position = CurvePoint(x: x, y: y)
    self.incoming = incoming ?? position
    self.outgoing = outgoing ?? position
    self.kind = kind
  }
}

/// Ordered cubic segments. Coordinates use normalized distance and blur strength, both 0...1.
public struct HaloCurve: Codable, Equatable, Sendable {
  public var nodes: [CurveNode]
  public init() {
    nodes = [
      CurveNode(x: 0, y: 0, outgoing: CurvePoint(x: 0.42, y: 0)),
      CurveNode(x: 1, y: 1, incoming: CurvePoint(x: 0.58, y: 1)),
    ]
  }

  public func validate() throws {
    guard nodes.count >= 2 else {
      throw RecipeError.invalid("A blur curve needs at least two points")
    }
    for node in nodes {
      for point in [node.position, node.incoming, node.outgoing] {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x),
          (0...1).contains(point.y)
        else {
          throw RecipeError.invalid("Curve coordinates must be finite and between 0 and 1")
        }
      }
    }
    for (left, right) in zip(nodes, nodes.dropFirst()) {
      guard left.position.x < right.position.x,
        (left.position.x...right.position.x).contains(left.outgoing.x),
        (left.position.x...right.position.x).contains(right.incoming.x)
      else {
        throw RecipeError.invalid("Curve points must be ordered, with handles inside their segment")
      }
    }
    for index in [0, nodes.count - 1] where nodes[index].kind != .corner {
      throw RecipeError.invalid(
        "Curve endpoint \(index + 1) has one handle, so it must be a corner")
    }
    for (index, node) in nodes.enumerated() where node.kind != .corner {
      let incoming = Self.offset(node.incoming, from: node.position)
      let outgoing = Self.offset(node.outgoing, from: node.position)
      let inLength = hypot(incoming.x, incoming.y)
      let outLength = hypot(outgoing.x, outgoing.y)
      let aligned =
        inLength < Self.collapsed || outLength < Self.collapsed
        || (abs(incoming.x * outgoing.y - incoming.y * outgoing.x) <= 1e-7 * inLength * outLength
          && incoming.x * outgoing.x + incoming.y * outgoing.y < 0)
      guard aligned else {
        throw RecipeError.invalid(
          "Curve point \(index + 1) is \(node.kind.rawValue) but its handles are not on one line")
      }
      guard node.kind != .symmetric || abs(inLength - outLength) <= 1e-7 else {
        throw RecipeError.invalid(
          "Curve point \(index + 1) is symmetric but its handles differ in length")
      }
    }
  }

  public func value(at x: Double) -> Double {
    guard let first = nodes.first, let last = nodes.last else { return 0 }
    if x <= first.position.x { return first.position.y }
    if x >= last.position.x { return last.position.y }
    guard let index = nodes.indices.dropLast().first(where: { x <= nodes[$0 + 1].position.x })
    else { return last.position.y }
    return point(in: index, at: parameter(in: index, x: x)).y
  }

  private func point(in index: Int, at t: Double) -> CurvePoint {
    let a = nodes[index]
    let b = nodes[index + 1]
    let q0 = a.position.mixed(with: a.outgoing, at: t)
    let q1 = a.outgoing.mixed(with: b.incoming, at: t)
    let q2 = b.incoming.mixed(with: b.position, at: t)
    return q0.mixed(with: q1, at: t).mixed(with: q1.mixed(with: q2, at: t), at: t)
  }

  private func parameter(in index: Int, x: Double) -> Double {
    var low = 0.0
    var high = 1.0
    for _ in 0..<36 {
      let middle = (low + high) / 2
      if point(in: index, at: middle).x < x { low = middle } else { high = middle }
    }
    return (low + high) / 2
  }

  /// Adds a point. Inside the curve it splits a segment; points added on the curve keep its shape
  /// and are smooth. Beyond either end the new point becomes the corner endpoint.
  @discardableResult public mutating func insert(at proposed: CurvePoint) -> Int? {
    let p = clamped(proposed)
    guard !nodes.contains(where: { abs($0.position.x - p.x) < 0.002 }) else { return nil }
    if p.x < nodes[0].position.x {
      let next = nodes[0].position
      nodes[0].incoming = p.mixed(with: next, at: 2 / 3)
      nodes.insert(CurveNode(x: p.x, y: p.y, outgoing: p.mixed(with: next, at: 1 / 3)), at: 0)
      return 0
    }
    if p.x > nodes[nodes.count - 1].position.x {
      let previous = nodes[nodes.count - 1].position
      nodes[nodes.count - 1].outgoing = previous.mixed(with: p, at: 1 / 3)
      nodes.append(CurveNode(x: p.x, y: p.y, incoming: previous.mixed(with: p, at: 2 / 3)))
      return nodes.count - 1
    }
    guard let i = nodes.indices.dropLast().first(where: { p.x < nodes[$0 + 1].position.x }) else {
      return nil
    }
    // De Casteljau subdivision preserves the existing curve when adding a point on it.
    let t = parameter(in: i, x: p.x)
    let a = nodes[i]
    let b = nodes[i + 1]
    let q0 = a.position.mixed(with: a.outgoing, at: t)
    let q1 = a.outgoing.mixed(with: b.incoming, at: t)
    let q2 = b.incoming.mixed(with: b.position, at: t)
    var incoming = q0.mixed(with: q1, at: t)
    var outgoing = q1.mixed(with: q2, at: t)
    let original = incoming.mixed(with: outgoing, at: t)
    incoming.y += p.y - original.y
    outgoing.y += p.y - original.y
    nodes[i].outgoing = q0
    nodes[i + 1].incoming = q2
    // Splitting shortens the neighbours' handles on the same lines: they stay aligned, but a
    // symmetric neighbour's lengths no longer match.
    for neighbour in [i, i + 1] where nodes[neighbour].kind == .symmetric {
      nodes[neighbour].kind = .smooth
    }
    nodes.insert(
      CurveNode(
        x: p.x, y: p.y, incoming: clamped(incoming), outgoing: clamped(outgoing), kind: .smooth),
      at: i + 1)
    // Clamping into the unit square can bend the split handles; realign them.
    constrain(i + 1, leading: .outgoing)
    return i + 1
  }

  public mutating func moveNode(_ index: Int, to proposed: CurvePoint) {
    guard nodes.indices.contains(index) else { return }
    let low = index == 0 ? 0 : nodes[index - 1].position.x + 0.001
    let high = index == nodes.count - 1 ? 1 : nodes[index + 1].position.x - 0.001
    guard low <= high else { return }
    var point = clamped(proposed)
    point.x = min(high, max(low, point.x))
    let old = nodes[index].position
    for incoming in [true, false] {
      var handle = incoming ? nodes[index].incoming : nodes[index].outgoing
      handle.x += point.x - old.x
      handle.y += point.y - old.y
      if incoming {
        nodes[index].incoming = clamped(handle)
      } else {
        nodes[index].outgoing = clamped(handle)
      }
    }
    nodes[index].position = point
    normalizeHandles()
  }

  /// Moves one handle; smooth and symmetric points then turn the other handle to match.
  public mutating func moveHandle(_ index: Int, incoming: Bool, to proposed: CurvePoint) {
    guard nodes.indices.contains(index) else { return }
    let bounds = handleBounds(index, incoming: incoming)
    var point = clamped(proposed)
    point.x = min(bounds.upperBound, max(bounds.lowerBound, point.x))
    if incoming { nodes[index].incoming = point } else { nodes[index].outgoing = point }
    constrain(index, leading: incoming ? .incoming : .outgoing)
  }

  /// Changes how a point's handles relate. Endpoints have one handle and remain corners.
  public mutating func setKind(_ kind: CurvePointKind, at index: Int) {
    guard isInterior(index), nodes[index].kind != kind else { return }
    nodes[index].kind = kind
    guard kind != .corner else { return }
    let node = nodes[index]
    let incoming = Self.offset(node.incoming, from: node.position)
    let outgoing = Self.offset(node.outgoing, from: node.position)
    var inLength = hypot(incoming.x, incoming.y)
    var outLength = hypot(outgoing.x, outgoing.y)
    var direction: CurvePoint
    switch (inLength >= Self.collapsed, outLength >= Self.collapsed) {
    case (true, true):
      // Bisect the two handle directions so the point's tangent turns as little as possible.
      direction = CurvePoint(
        x: outgoing.x / outLength - incoming.x / inLength,
        y: outgoing.y / outLength - incoming.y / inLength)
    case (false, true): direction = outgoing
    case (true, false): direction = CurvePoint(x: -incoming.x, y: -incoming.y)
    case (false, false):
      // No handles yet: follow the neighbours, a third of the way to each.
      let previous = nodes[index - 1].position
      let next = nodes[index + 1].position
      direction = Self.offset(next, from: previous)
      inLength = hypot(node.position.x - previous.x, node.position.y - previous.y) / 3
      outLength = hypot(next.x - node.position.x, next.y - node.position.y) / 3
    }
    if kind == .symmetric {
      (inLength, outLength) = ((inLength + outLength) / 2, (inLength + outLength) / 2)
    }
    align(index, direction: direction, inLength: inLength, outLength: outLength)
  }

  @discardableResult public mutating func remove(at index: Int) -> Bool {
    guard nodes.count > 2, nodes.indices.contains(index) else { return false }
    nodes.remove(at: index)
    normalizeHandles()
    return true
  }

  // MARK: - Handle constraints

  private enum Handle { case incoming, outgoing }
  /// Handles shorter than this have no direction.
  private static let collapsed = 1e-9

  private static func offset(_ point: CurvePoint, from origin: CurvePoint) -> CurvePoint {
    CurvePoint(x: point.x - origin.x, y: point.y - origin.y)
  }

  private func isInterior(_ index: Int) -> Bool { index > 0 && index < nodes.count - 1 }

  /// A handle's X stays within its own segment; endpoints have no outer segment.
  private func handleBounds(_ index: Int, incoming: Bool) -> ClosedRange<Double> {
    let x = nodes[index].position.x
    if incoming { return index > 0 ? nodes[index - 1].position.x...x : x...x }
    return index < nodes.count - 1 ? x...nodes[index + 1].position.x : x...x
  }

  /// Re-establishes a smooth or symmetric point after one handle (`leading`) moved.
  private mutating func constrain(_ index: Int, leading: Handle) {
    guard isInterior(index), nodes[index].kind != .corner else { return }
    let node = nodes[index]
    let incoming = Self.offset(node.incoming, from: node.position)
    let outgoing = Self.offset(node.outgoing, from: node.position)
    let inLength = hypot(incoming.x, incoming.y)
    let outLength = hypot(outgoing.x, outgoing.y)
    let leadLength = leading == .incoming ? inLength : outLength
    guard leadLength >= Self.collapsed else { return }
    let direction = leading == .incoming ? CurvePoint(x: -incoming.x, y: -incoming.y) : outgoing
    let symmetric = node.kind == .symmetric
    align(
      index, direction: direction, inLength: symmetric ? leadLength : inLength,
      outLength: symmetric ? leadLength : outLength)
  }

  /// Places both handles on one line through the point, `direction` pointing to the outgoing side.
  /// A handle that would leave its segment or the unit square is shortened along that line;
  /// symmetric points shorten both.
  private mutating func align(
    _ index: Int, direction: CurvePoint, inLength: Double, outLength: Double
  ) {
    let length = hypot(direction.x, direction.y)
    guard length >= Self.collapsed else { return }
    let unit = CurvePoint(x: direction.x / length, y: direction.y / length)
    let position = nodes[index].position
    var outReach = min(
      outLength, reach(from: position, along: unit, xRange: handleBounds(index, incoming: false)))
    let backward = CurvePoint(x: -unit.x, y: -unit.y)
    var inReach = min(
      inLength, reach(from: position, along: backward, xRange: handleBounds(index, incoming: true)))
    if nodes[index].kind == .symmetric {
      (inReach, outReach) = (min(inReach, outReach), min(inReach, outReach))
    }
    nodes[index].outgoing = CurvePoint(
      x: position.x + unit.x * outReach, y: position.y + unit.y * outReach)
    nodes[index].incoming = CurvePoint(
      x: position.x - unit.x * inReach, y: position.y - unit.y * inReach)
  }

  /// The farthest distance from `origin` along `unit` that stays inside `xRange` × 0...1.
  private func reach(from origin: CurvePoint, along unit: CurvePoint, xRange: ClosedRange<Double>)
    -> Double
  {
    func limit(_ position: Double, _ step: Double, _ range: ClosedRange<Double>) -> Double {
      if step > 0 { return (range.upperBound - position) / step }
      if step < 0 { return (range.lowerBound - position) / step }
      return .infinity
    }
    return max(0, min(limit(origin.x, unit.x, xRange), limit(origin.y, unit.y, 0...1)))
  }

  private func clamped(_ p: CurvePoint) -> CurvePoint {
    CurvePoint(x: min(1, max(0, p.x)), y: min(1, max(0, p.y)))
  }

  /// After points move or disappear: endpoints become corners without an outer handle, handles
  /// return inside their segments, and smooth points realign.
  private mutating func normalizeHandles() {
    nodes[0].kind = .corner
    nodes[0].incoming = nodes[0].position
    nodes[nodes.count - 1].kind = .corner
    nodes[nodes.count - 1].outgoing = nodes[nodes.count - 1].position
    for index in nodes.indices {
      for incoming in [true, false] {
        let bounds = handleBounds(index, incoming: incoming)
        var handle = incoming ? nodes[index].incoming : nodes[index].outgoing
        handle.x = min(bounds.upperBound, max(bounds.lowerBound, handle.x))
        if incoming { nodes[index].incoming = handle } else { nodes[index].outgoing = handle }
      }
      constrain(index, leading: .outgoing)
    }
  }
}
