import AppKit
import XCTest

/// RGBA pixels of a rendered view, with the origin at the top left like the flipped backdrop.
struct Pixels {
  let width: Int
  let height: Int
  private let bytes: [UInt8]

  init(_ bitmap: NSBitmapImageRep) throws {
    width = bitmap.pixelsWide
    height = bitmap.pixelsHigh
    let image = try XCTUnwrap(bitmap.cgImage)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    self.bytes = bytes
  }

  func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
  }

  private func isRed(_ x: Int, _ y: Int) -> Bool {
    let (r, g, b) = rgb(x, y)
    return r > 220 && g < 110 && b < 100
  }

  private func isYellow(_ x: Int, _ y: Int) -> Bool {
    let (r, g, b) = rgb(x, y)
    return r > 220 && g > 150 && b < 90
  }

  /// Window close buttons: round red blobs with the yellow minimize button 23 pt to the right.
  func closeButtons(scale: Double) -> [CGRect] {
    var seen = Set<Int>()
    var buttons: [CGRect] = []
    for y in 0..<height {
      for x in 0..<width where isRed(x, y) && !seen.contains(y * width + x) {
        var stack = [(x, y)]
        var (minX, maxX, minY, maxY, count) = (x, x, y, y, 0)
        seen.insert(y * width + x)
        while let (px, py) = stack.popLast() {
          count += 1
          (minX, maxX, minY, maxY) = (min(minX, px), max(maxX, px), min(minY, py), max(maxY, py))
          for (nx, ny) in [(px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)]
          where nx >= 0 && ny >= 0 && nx < width && ny < height && isRed(nx, ny)
            && !seen.contains(ny * width + nx)
          {
            seen.insert(ny * width + nx)
            stack.append((nx, ny))
          }
        }
        let w = Double(maxX - minX + 1)
        let h = Double(maxY - minY + 1)
        let fill = Double(count) / (w * h)
        let yellowX = (minX + maxX) / 2 + Int((23 * scale).rounded())
        guard w / scale >= 8, w / scale <= 20, abs(w - h) <= 1, fill > 0.65, fill < 0.9,
          yellowX < width, isYellow(yellowX, (minY + maxY) / 2)
        else { continue }
        buttons.append(CGRect(x: Double(minX), y: Double(minY), width: w, height: h))
      }
    }
    return buttons
  }

  /// Rows of the title bar: from the window's top edge down to the separator under the bar,
  /// following the bar's own colour in the column just right of the button.
  func titleBar(beside button: CGRect) -> Range<Int> {
    let x = Int(button.maxX) + 3
    let y = Int(button.midY)
    let bar = rgb(x, y)
    func differs(_ row: Int) -> Bool {
      let (r, g, b) = rgb(x, row)
      return abs(r - bar.0) + abs(g - bar.1) + abs(b - bar.2) > 6
    }
    var top = y
    while top > 0 && !differs(top - 1) { top -= 1 }
    var bottom = y
    while bottom < height - 1 && !differs(bottom + 1) { bottom += 1 }
    return top..<(bottom + 1)
  }
}
