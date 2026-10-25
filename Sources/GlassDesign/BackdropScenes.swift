import AppKit

/// Draws one backdrop scene into the current (flipped) graphics context. Colors are AppKit's
/// semantic colors, resolved under the backdrop's appearance, so both themes use the system palette.
@MainActor
struct SceneRenderer {
  let bounds: CGRect
  let wallpaper: CGImage?
  let photos: [CGImage]
  let dark: Bool

  func draw(_ scene: BackdropScene) {
    switch scene {
    case .desktop: drawDesktop()
    case .article: drawArticle()
    case .code: drawCode()
    case .photos: drawPhotos()
    }
  }

  // MARK: - Desktop

  private func drawDesktop() {
    fill(image: wallpaper, in: bounds)
    drawMenuBar()
    let finder = CGRect(
      x: bounds.width * 0.05, y: 58, width: bounds.width * 0.6, height: bounds.height * 0.5)
    let finderContent = window(finder, title: "Documents")
    drawFinder(in: finderContent)
    let notes = CGRect(
      x: bounds.width * 0.4, y: bounds.height * 0.34, width: bounds.width * 0.55,
      height: bounds.height * 0.44)
    drawNotes(in: window(notes, title: "Glass Notes"))
    drawDock()
  }

  private func drawMenuBar() {
    let bar = CGRect(x: 0, y: 0, width: bounds.width, height: 26)
    (dark ? NSColor.black.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.4))
      .setFill()
    bar.fill()
    symbol("applelogo", in: CGRect(x: 14, y: 5, width: 15, height: 16), color: .labelColor)
    var x: CGFloat = 44
    for (index, item) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
      let font = NSFont.systemFont(ofSize: 13, weight: index == 0 ? .bold : .regular)
      x += text(item, at: CGPoint(x: x, y: 5), font: font, color: .labelColor).width + 18
    }
    let clock = "Fri Oct 24  10:48"
    let clockWidth = measure(clock, font: .systemFont(ofSize: 13))
    text(
      clock, at: CGPoint(x: bounds.width - clockWidth - 14, y: 5), font: .systemFont(ofSize: 13),
      color: .labelColor)
    var symbolX = bounds.width - clockWidth - 40
    for name in ["magnifyingglass", "wifi", "battery.75percent"] {
      symbol(name, in: CGRect(x: symbolX, y: 5, width: 18, height: 16), color: .labelColor)
      symbolX -= 30
    }
  }

  private func drawFinder(in content: CGRect) {
    let sidebar = CGRect(x: content.minX, y: content.minY, width: 168, height: content.height)
    sidebarBackground(sidebar)
    sidebarList(
      [
        ("Favorites", nil), ("AirDrop", "dot.radiowaves.left.and.right"), ("Recents", "clock"),
        ("Applications", "square.grid.2x2"), ("Desktop", "menubar.dock.rectangle"),
        ("Documents", "doc"), ("Downloads", "arrow.down.circle"), ("Locations", nil),
        ("iCloud Drive", "icloud"), ("Macintosh HD", "internaldrive"),
      ], selected: "Documents", in: sidebar)
    let list = CGRect(
      x: sidebar.maxX, y: content.minY, width: content.maxX - sidebar.maxX, height: content.height)
    NSColor.textBackgroundColor.setFill()
    list.fill()
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    list.clip()
    let columns: [(String, CGFloat)] = [("Name", 0), ("Date Modified", 0.55), ("Size", 0.84)]
    for (title, offset) in columns {
      text(
        title, at: CGPoint(x: list.minX + 12 + list.width * offset, y: list.minY + 6),
        font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    }
    separator(y: list.minY + 24, from: list.minX, to: list.maxX)
    let rows: [(String, NSColor, String, String, String)] = [
      ("Glass Recipes", .systemBlue, "folder.fill", "Today at 09:12", "--"),
      ("Halo study.heic", .systemTeal, "photo.fill", "Today at 08:47", "4.2 MB"),
      ("Toolbar spec.pdf", .systemRed, "doc.richtext.fill", "Yesterday", "812 KB"),
      ("Refraction notes.md", .secondaryLabelColor, "doc.text.fill", "Yesterday", "14 KB"),
      ("Palette.sketch", .systemOrange, "paintpalette.fill", "Oct 21", "2.8 MB"),
      ("Motion timing.mov", .systemPurple, "film.fill", "Oct 20", "38.1 MB"),
      ("Launch deck.key", .systemBlue, "rectangle.on.rectangle.angled.fill", "Oct 18", "61 MB"),
      ("Sound cues", .systemBlue, "folder.fill", "Oct 16", "--"),
      ("Contrast audit.numbers", .systemGreen, "tablecells.fill", "Oct 12", "320 KB"),
      ("Archive.zip", .secondaryLabelColor, "doc.zipper", "Oct 3", "122 MB"),
    ]
    let alternating = NSColor.alternatingContentBackgroundColors
    for (index, row) in rows.enumerated() {
      let rect = CGRect(
        x: list.minX, y: list.minY + 26 + CGFloat(index) * 24, width: list.width, height: 24)
      guard rect.maxY <= list.maxY else { break }
      alternating[index % alternating.count].setFill()
      rect.fill()
      if index == 2 {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
      }
      let color: NSColor = index == 2 ? .alternateSelectedControlTextColor : .labelColor
      symbol(
        row.2, in: CGRect(x: rect.minX + 12, y: rect.minY + 4, width: 18, height: 16),
        color: index == 2 ? color : row.1)
      text(
        row.0, at: CGPoint(x: rect.minX + 38, y: rect.minY + 4), font: .systemFont(ofSize: 13),
        color: color)
      for (value, offset) in [(row.3, 0.55), (row.4, 0.84)] {
        text(
          value, at: CGPoint(x: rect.minX + 12 + rect.width * offset, y: rect.minY + 4),
          font: .systemFont(ofSize: 12),
          color: index == 2 ? color : .secondaryLabelColor)
      }
    }
  }

  private func drawNotes(in content: CGRect) {
    NSColor.textBackgroundColor.setFill()
    content.fill()
    var y = content.minY + 18
    let x = content.minX + 24
    let width = content.width - 48
    y +=
      paragraph(
        "Ideas for the floating toolbar", x: x, y: y, width: width,
        font: .systemFont(ofSize: 22, weight: .bold), color: .labelColor) + 10
    for (done, item) in [
      (true, "Keep the toolbar legible over photos and text"),
      (true, "Merge neighbouring buttons when they come closer than 8 pt"),
      (false, "Test the tint against the dark sidebar"),
      (false, "Soften the halo where it meets the dock"),
    ] {
      symbol(
        done ? "checkmark.circle.fill" : "circle",
        in: CGRect(x: x, y: y + 1, width: 16, height: 16),
        color: done ? .controlAccentColor : .tertiaryLabelColor)
      y +=
        paragraph(
          item, x: x + 26, y: y, width: width - 26, font: .systemFont(ofSize: 14),
          color: done ? .secondaryLabelColor : .labelColor) + 8
    }
    y += 6
    paragraph(
      "Glass reads its surroundings: refraction bends the edges of whatever passes beneath it, and the blur softens fine detail into colour. Text and photos make the effect easy to judge, so the surface should be tried over both before the recipe is final.",
      x: x, y: y, width: width, font: .systemFont(ofSize: 14), color: .labelColor, lineSpacing: 4)
  }

  private func drawDock() {
    let names: [(String, NSColor, NSColor)] = [
      ("folder.fill", .systemBlue, .systemCyan), ("safari", .systemBlue, .systemTeal),
      ("message.fill", .systemGreen, .systemMint), ("envelope.fill", .systemBlue, .systemIndigo),
      ("map.fill", .systemGreen, .systemYellow), ("photo", .systemOrange, .systemPink),
      ("music.note", .systemPink, .systemRed), ("calendar", .systemRed, .systemOrange),
      ("note.text", .systemYellow, .systemOrange), ("gearshape.fill", .systemGray, .darkGray),
    ]
    let size: CGFloat = 50
    let width = CGFloat(names.count) * (size + 10) + 14
    let dock = CGRect(
      x: (bounds.width - width) / 2, y: bounds.height - size - 26, width: width, height: size + 16)
    (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.38))
      .setFill()
    let shape = NSBezierPath(roundedRect: dock, xRadius: 22, yRadius: 22)
    shape.fill()
    NSColor.white.withAlphaComponent(dark ? 0.2 : 0.55).setStroke()
    shape.stroke()
    for (index, icon) in names.enumerated() {
      let rect = CGRect(
        x: dock.minX + 12 + CGFloat(index) * (size + 10), y: dock.minY + 8, width: size,
        height: size)
      let tile = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
      NSGradient(starting: icon.2, ending: icon.1)?.draw(in: tile, angle: -90)
      symbol(icon.0, in: rect.insetBy(dx: 12, dy: 12), color: .white)
    }
  }

  // MARK: - Article

  private func drawArticle() {
    let content = window(bounds, title: "", framed: false)
    // Address field in the unified toolbar.
    let field = toolbarItem(x: bounds.midX - 170, width: 340, height: 26)
    NSColor.quaternaryLabelColor.setFill()
    NSBezierPath(roundedRect: field, xRadius: 7, yRadius: 7).fill()
    symbol(
      "lock.fill", in: CGRect(x: field.minX + 10, y: field.midY - 6, width: 10, height: 12),
      color: .secondaryLabelColor)
    text(
      "glass.example/design/materials", centredIn: field, x: field.minX + 26,
      font: .systemFont(ofSize: 13), color: .labelColor)
    for (index, name) in ["sidebar.left", "chevron.left", "chevron.right"].enumerated() {
      symbol(
        name, in: toolbarItem(x: 92 + CGFloat(index) * 30, width: 18, height: 16),
        color: .secondaryLabelColor)
    }
    for (index, name) in ["square.and.arrow.up", "plus", "square.on.square"].enumerated() {
      symbol(
        name, in: toolbarItem(x: bounds.width - 40 - CGFloat(index) * 32, width: 18, height: 16),
        color: .secondaryLabelColor)
    }
    NSColor.textBackgroundColor.setFill()
    content.fill()
    let width = min(620, content.width - 80)
    let x = content.minX + (content.width - width) / 2
    var y = content.minY + 36
    let kicker = NSAttributedString(
      string: "DESIGN",
      attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .kern: 1.6,
        .foregroundColor: NSColor.controlAccentColor,
      ])
    kicker.draw(at: CGPoint(x: x, y: y))
    y += 24
    y +=
      paragraph(
        "Light, depth, and the materials that hold an interface together", x: x, y: y,
        width: width, font: .systemFont(ofSize: 30, weight: .bold), color: .labelColor) + 12
    y +=
      paragraph(
        "By Riley Chen  ·  8 min read", x: x, y: y, width: width, font: .systemFont(ofSize: 13),
        color: .secondaryLabelColor) + 20
    let hero = CGRect(x: x, y: y, width: width, height: min(280, content.height * 0.3))
    fill(image: wallpaper, in: hero, radius: 10)
    y = hero.maxY + 8
    y +=
      paragraph(
        "A wallpaper seen through a sheet of glass changes with every degree of curvature.", x: x,
        y: y, width: width, font: .systemFont(ofSize: 12), color: .tertiaryLabelColor) + 22
    for body in [
      "Every surface on screen sits somewhere: above the content, beside it, or beneath it. Materials make that position visible. A translucent toolbar lets the page scroll behind it, so you always know there is more above; a frosted sidebar keeps the wallpaper's colour without its detail.",
      "Glass goes one step further. Its edges bend the light that passes through them, so text sliding underneath appears to stretch around the rim, and bright colours bleed softly inward.",
    ] {
      y +=
        paragraph(
          body, x: x, y: y, width: width, font: .systemFont(ofSize: 16), color: .labelColor,
          lineSpacing: 6) + 18
    }
    let quoteHeight = paragraph(
      "The best material is the one you notice only when it is gone.", x: x + 22, y: y,
      width: width - 22, font: .systemFont(ofSize: 22, weight: .semibold), color: .labelColor)
    NSColor.controlAccentColor.setFill()
    CGRect(x: x, y: y, width: 4, height: quoteHeight).fill()
    y += quoteHeight + 22
    paragraph(
      "Designers tune three things: how much the surface blurs, how strongly its rim refracts, and how much colour it borrows from below. Read more in the material guidelines, or compare the variants side by side.",
      x: x, y: y, width: width, font: .systemFont(ofSize: 16), color: .labelColor, lineSpacing: 6)
  }

  // MARK: - Code

  private func drawCode() {
    let content = window(bounds, title: "GlassCanvas.swift", titleX: 160, framed: false)
    for (index, name) in ["play.fill", "stop.fill"].enumerated() {
      symbol(
        name, in: toolbarItem(x: 94 + CGFloat(index) * 30, width: 16, height: 14),
        color: .secondaryLabelColor)
    }
    let navigator = CGRect(x: content.minX, y: content.minY, width: 200, height: content.height)
    sidebarBackground(navigator)
    let files: [(Int, String, String, NSColor)] = [
      (0, "GlassDesigner", "folder.fill", .systemBlue), (1, "Sources", "folder.fill", .systemBlue),
      (2, "BackdropView.swift", "swift", .systemOrange),
      (2, "CurveEditor.swift", "swift", .systemOrange),
      (2, "GlassCanvas.swift", "swift", .systemOrange),
      (2, "HaloCurve.swift", "swift", .systemOrange),
      (2, "HaloMask.swift", "swift", .systemOrange), (2, "Inspector.swift", "swift", .systemOrange),
      (1, "Tests", "folder.fill", .systemBlue),
      (1, "Package.swift", "shippingbox.fill", .systemBrown),
      (1, "README.md", "doc.text", .secondaryLabelColor),
    ]
    for (index, file) in files.enumerated() {
      let row = CGRect(
        x: navigator.minX + 8, y: navigator.minY + 10 + CGFloat(index) * 24,
        width: navigator.width - 16, height: 22)
      let selected = file.1 == "GlassCanvas.swift"
      if selected {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
      }
      let indent = row.minX + 6 + CGFloat(file.0) * 14
      symbol(
        file.2, in: CGRect(x: indent, y: row.minY + 3, width: 15, height: 15),
        color: selected ? .white : file.3)
      text(
        file.1, at: CGPoint(x: indent + 22, y: row.minY + 3), font: .systemFont(ofSize: 12),
        color: selected ? .alternateSelectedControlTextColor : .labelColor)
    }
    let palette = CodePalette(dark: dark)
    let editor = CGRect(
      x: navigator.maxX, y: content.minY, width: content.maxX - navigator.maxX,
      height: content.height)
    palette.background.setFill()
    editor.fill()
    let tabs = CGRect(x: editor.minX, y: editor.minY, width: editor.width, height: 30)
    NSColor.windowBackgroundColor.setFill()
    tabs.fill()
    for (index, name) in ["GlassCanvas.swift", "HaloMask.swift"].enumerated() {
      let tab = CGRect(x: tabs.minX + CGFloat(index) * 170, y: tabs.minY, width: 170, height: 30)
      if index == 0 {
        palette.background.setFill()
        tab.fill()
      }
      symbol(
        "swift", in: CGRect(x: tab.minX + 12, y: tab.minY + 8, width: 13, height: 13),
        color: .systemOrange)
      text(
        name, at: CGPoint(x: tab.minX + 32, y: tab.minY + 7), font: .systemFont(ofSize: 12),
        color: index == 0 ? .labelColor : .secondaryLabelColor)
    }
    separator(y: tabs.maxY, from: tabs.minX, to: tabs.maxX)
    let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    let lineHeight: CGFloat = 19
    let minimap = CGRect(
      x: editor.maxX - 64, y: tabs.maxY, width: 64, height: editor.maxY - tabs.maxY)
    for (index, line) in CodeSample.lines.enumerated() {
      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }
      CGRect(
        x: editor.minX, y: tabs.maxY, width: minimap.minX - editor.minX, height: minimap.height
      ).clip()
      let y = tabs.maxY + 10 + CGFloat(index) * lineHeight
      guard y + lineHeight <= editor.maxY else { break }
      if index == 11 {
        palette.currentLine.setFill()
        CGRect(x: editor.minX, y: y - 1, width: minimap.minX - editor.minX, height: lineHeight)
          .fill()
      }
      let number = "\(index + 1)" as NSString
      let numberWidth = measure(number as String, font: font)
      text(
        number as String, at: CGPoint(x: editor.minX + 38 - numberWidth, y: y), font: font,
        color: .tertiaryLabelColor)
      palette.highlighted(line, font: font).draw(at: CGPoint(x: editor.minX + 56, y: y))
      // The minimap repeats each line as a thin bar in its dominant colour.
      NSGraphicsContext.restoreGraphicsState()
      NSGraphicsContext.saveGraphicsState()
      let length = CGFloat(line.count) * 0.9
      if length > 0 {
        palette.color(for: line).withAlphaComponent(0.6).setFill()
        CGRect(
          x: minimap.minX + 8, y: minimap.minY + 8 + CGFloat(index) * 3, width: min(length, 48),
          height: 2
        ).fill()
      }
    }
    NSColor.separatorColor.setFill()
    CGRect(x: minimap.minX, y: minimap.minY, width: 1, height: minimap.height).fill()
  }

  // MARK: - Photos

  private func drawPhotos() {
    let content = window(bounds, title: "Library", framed: false)
    let segments = ["Years", "Months", "Days", "All Photos"]
    var x = bounds.midX - 150
    let pill = toolbarItem(x: x - 3, width: 306, height: 26)
    NSColor.quaternaryLabelColor.setFill()
    NSBezierPath(roundedRect: pill, xRadius: 7, yRadius: 7).fill()
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    for (index, segment) in segments.enumerated() {
      let segmentRect = toolbarItem(x: x, width: index == 3 ? 92 : 68, height: 20)
      if index == 3 {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: segmentRect, xRadius: 5, yRadius: 5).fill()
      }
      text(
        segment, centredIn: segmentRect, x: segmentRect.midX - measure(segment, font: font) / 2,
        font: font, color: .labelColor)
      x += segmentRect.width
    }
    let sidebar = CGRect(x: content.minX, y: content.minY, width: 190, height: content.height)
    sidebarBackground(sidebar)
    sidebarList(
      [
        ("Photos", nil), ("Library", "photo.on.rectangle"), ("Collections", "rectangle.stack"),
        ("Pinned", nil), ("Favourites", "heart"), ("Recently Saved", "clock.arrow.circlepath"),
        ("Map", "map"), ("Videos", "video"), ("Screenshots", "camera.viewfinder"),
        ("People & Pets", "person.crop.circle"),
      ], selected: "Library", in: sidebar)
    let grid = CGRect(
      x: sidebar.maxX, y: content.minY, width: content.maxX - sidebar.maxX, height: content.height)
    NSColor.windowBackgroundColor.setFill()
    grid.fill()
    var y = grid.minY + 18
    text(
      "Tahoe Lake", at: CGPoint(x: grid.minX + 18, y: y),
      font: .systemFont(ofSize: 20, weight: .bold), color: .labelColor)
    y += 28
    text(
      "24 October 2026  ·  36 photos", at: CGPoint(x: grid.minX + 18, y: y),
      font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
    y += 30
    let columns = 4
    let gap: CGFloat = 3
    let tile = (grid.width - 36 - gap * CGFloat(columns - 1)) / CGFloat(columns)
    // Step through the photos with a stride that shares no factor with their count, so
    // neighbouring tiles never repeat a picture. Among any `count` consecutive candidates one is
    // 1 more than a multiple of `count`, so the search is bounded; with no photos yet (they are
    // still decoding) there is nothing to step through.
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    let stride = (5..<(5 + max(photos.count, 1))).first { gcd($0, photos.count) == 1 } ?? 1
    var index = 0
    while y + tile <= grid.maxY + tile * 0.6 {
      for column in 0..<columns {
        let rect = CGRect(
          x: grid.minX + 18 + CGFloat(column) * (tile + gap), y: y, width: tile, height: tile)
        if photos.isEmpty {
          NSColor.quaternaryLabelColor.setFill()
          rect.fill()
        } else {
          let photo = photos[(index * stride) % photos.count]
          fill(image: crop(photo, variant: index), in: rect)
        }
        if index % 5 == 1 {
          symbol(
            "heart.fill", in: CGRect(x: rect.minX + 8, y: rect.maxY - 22, width: 14, height: 13),
            color: .white)
        }
        if index % 7 == 3 {
          text(
            "0:42", at: CGPoint(x: rect.maxX - 34, y: rect.maxY - 22),
            font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
        }
        index += 1
      }
      y += tile + gap
    }
  }

  /// A different region and zoom of the same wallpaper reads as a different photo.
  private func crop(_ image: CGImage, variant: Int) -> CGImage {
    let zoom = [1.0, 1.7, 2.6, 3.4][variant % 4]
    let side = Double(min(image.width, image.height)) / zoom
    let spanX = Double(image.width) - side
    let spanY = Double(image.height) - side
    let fx = Double((variant * 37) % 100) / 100
    let fy = Double((variant * 61) % 100) / 100
    return image.cropping(to: CGRect(x: spanX * fx, y: spanY * fy, width: side, height: side))
      ?? image
  }

  // MARK: - Window chrome

  /// Every scene window uses AppKit's unified compact title bar, as measured on macOS 26:
  /// 40 pt tall, with 14 pt window buttons at x 12, 35, and 58, centred in the bar.
  private static let titleBarHeight: CGFloat = 40
  private static let windowButtonSize: CGFloat = 14
  private static let windowButtonX: [CGFloat] = [12, 35, 58]
  /// Where a title starts when no toolbar items sit between it and the window buttons.
  private static let titleX: CGFloat = 90

  /// A toolbar item of the given height, vertically centred in the title bar of a window at `top`.
  private func toolbarItem(x: CGFloat, width: CGFloat, height: CGFloat, top: CGFloat = 0)
    -> CGRect
  {
    CGRect(x: x, y: top + (Self.titleBarHeight - height) / 2, width: width, height: height)
  }

  /// Draws a window with a unified compact title bar and returns its content area. `framed`
  /// windows float with rounded corners and a shadow; unframed ones fill the stage.
  private func window(
    _ frame: CGRect, title: String, titleX: CGFloat = SceneRenderer.titleX, framed: Bool = true
  ) -> CGRect {
    let titleHeight = Self.titleBarHeight
    let chromeless = !framed
    let shape = NSBezierPath(
      roundedRect: frame, xRadius: chromeless ? 0 : 14, yRadius: chromeless ? 0 : 14)
    if !chromeless {
      NSGraphicsContext.saveGraphicsState()
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.28)
      shadow.shadowBlurRadius = 28
      shadow.shadowOffset = NSSize(width: 0, height: -10)
      shadow.set()
      NSColor.windowBackgroundColor.setFill()
      shape.fill()
      NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSColor.windowBackgroundColor.setFill()
    frame.fill()
    let size = Self.windowButtonSize
    for (x, color) in zip(Self.windowButtonX, [NSColor.systemRed, .systemYellow, .systemGreen]) {
      color.setFill()
      NSBezierPath(
        ovalIn: toolbarItem(x: frame.minX + x, width: size, height: size, top: frame.minY)
      ).fill()
    }
    if !title.isEmpty {
      let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
      let height = NSAttributedString(string: title, attributes: [.font: font]).size().height
      text(
        title, at: CGPoint(x: frame.minX + titleX, y: frame.minY + (titleHeight - height) / 2),
        font: font, color: .labelColor)
    }
    separator(y: frame.minY + titleHeight, from: frame.minX, to: frame.maxX)
    NSGraphicsContext.restoreGraphicsState()
    if !chromeless {
      NSColor.separatorColor.setStroke()
      shape.stroke()
    }
    return CGRect(
      x: frame.minX, y: frame.minY + titleHeight + 1, width: frame.width,
      height: frame.height - titleHeight - 1)
  }

  private func sidebarBackground(_ rect: CGRect) {
    NSColor.windowBackgroundColor.blended(withFraction: dark ? 0.06 : 0.04, of: .labelColor)?
      .setFill()
    rect.fill()
    NSColor.separatorColor.setFill()
    CGRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
  }

  /// Rows with a symbol are items; rows without one are section headings.
  private func sidebarList(_ rows: [(String, String?)], selected: String, in sidebar: CGRect) {
    var y = sidebar.minY + 12
    for (title, symbolName) in rows {
      guard let symbolName else {
        y += 6
        text(
          title, at: CGPoint(x: sidebar.minX + 14, y: y),
          font: .systemFont(ofSize: 11, weight: .semibold), color: .tertiaryLabelColor)
        y += 20
        continue
      }
      let row = CGRect(x: sidebar.minX + 8, y: y, width: sidebar.width - 16, height: 24)
      if title == selected {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: row, xRadius: 6, yRadius: 6).fill()
      }
      symbol(
        symbolName, in: CGRect(x: row.minX + 8, y: row.minY + 4, width: 16, height: 16),
        color: .controlAccentColor)
      text(
        title, at: CGPoint(x: row.minX + 32, y: row.minY + 4), font: .systemFont(ofSize: 13),
        color: .labelColor)
      y += 26
    }
  }

  // MARK: - Primitives

  private func fill(image: CGImage?, in rect: CGRect, radius: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    guard let image else {
      // While a wallpaper decodes, keep the space a neutral mid-tone of the theme.
      NSColor.underPageBackgroundColor.setFill()
      rect.fill()
      NSGraphicsContext.restoreGraphicsState()
      return
    }
    let size = CGSize(width: image.width, height: image.height)
    let scale = max(rect.width / size.width, rect.height / size.height)
    let drawn = CGRect(
      x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2,
      width: size.width * scale, height: size.height * scale)
    NSImage(cgImage: image, size: size).draw(
      in: drawn, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
  }

  private func symbol(_ name: String, in rect: CGRect, color: NSColor) {
    guard
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    else { return }
    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    image.draw(
      in: CGRect(
        x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width,
        height: size.height),
      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
  }

  @discardableResult
  private func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor) -> CGSize {
    let text = NSAttributedString(
      string: string, attributes: [.font: font, .foregroundColor: color])
    text.draw(at: point)
    return text.size()
  }

  /// Draws one line of text starting at `x`, vertically centred in `rect`.
  private func text(
    _ string: String, centredIn rect: CGRect, x: CGFloat, font: NSFont, color: NSColor
  ) {
    let height = NSAttributedString(string: string, attributes: [.font: font]).size().height
    text(string, at: CGPoint(x: x, y: rect.midY - height / 2), font: font, color: color)
  }

  private func measure(_ string: String, font: NSFont) -> CGFloat {
    NSAttributedString(string: string, attributes: [.font: font]).size().width
  }

  /// Draws wrapped text and returns its height.
  @discardableResult
  private func paragraph(
    _ string: String, x: CGFloat, y: CGFloat, width: CGFloat, font: NSFont, color: NSColor,
    lineSpacing: CGFloat = 0
  ) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = lineSpacing
    let text = NSAttributedString(
      string: string,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let size = text.boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).size
    text.draw(
      with: CGRect(x: x, y: y, width: width, height: ceil(size.height)),
      options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(size.height)
  }

  private func separator(y: CGFloat, from minX: CGFloat, to maxX: CGFloat) {
    NSColor.separatorColor.setFill()
    CGRect(x: minX, y: y, width: maxX - minX, height: 1).fill()
  }
}
