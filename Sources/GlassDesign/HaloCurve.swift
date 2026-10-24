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

public struct CurveNode: Codable, Equatable, Sendable {
  public var position: CurvePoint
  public var incoming: CurvePoint
  public var outgoing: CurvePoint
  public init(x: Double, y: Double, incoming: CurvePoint? = nil, outgoing: CurvePoint? = nil) {
    position = CurvePoint(x: x, y: y)
    self.incoming = incoming ?? position
    self.outgoing = outgoing ?? position
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
    nodes.insert(
      CurveNode(x: p.x, y: p.y, incoming: clamped(incoming), outgoing: clamped(outgoing)), at: i + 1
    )
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

  public mutating func moveHandle(_ index: Int, incoming: Bool, to proposed: CurvePoint) {
    guard nodes.indices.contains(index) else { return }
    let low = incoming && index > 0 ? nodes[index - 1].position.x : nodes[index].position.x
    let high =
      !incoming && index < nodes.count - 1 ? nodes[index + 1].position.x : nodes[index].position.x
    var point = clamped(proposed)
    point.x = min(high, max(low, point.x))
    if incoming { nodes[index].incoming = point } else { nodes[index].outgoing = point }
  }

  @discardableResult public mutating func remove(at index: Int) -> Bool {
    guard nodes.count > 2, nodes.indices.contains(index) else { return false }
    nodes.remove(at: index)
    normalizeHandles()
    return true
  }

  private func clamped(_ p: CurvePoint) -> CurvePoint {
    CurvePoint(x: min(1, max(0, p.x)), y: min(1, max(0, p.y)))
  }
  private mutating func normalizeHandles() {
    for index in nodes.indices {
      moveHandle(index, incoming: true, to: nodes[index].incoming)
      moveHandle(index, incoming: false, to: nodes[index].outgoing)
    }
  }
}
