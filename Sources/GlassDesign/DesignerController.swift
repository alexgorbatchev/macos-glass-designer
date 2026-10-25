import AppKit
import UniformTypeIdentifiers

extension UTType {
  /// Recipe JSON on the clipboard; declared under UTExportedTypeDeclarations in Info.plist.
  static let glassRecipe = UTType(
    exportedAs: "com.alexgorbatchev.glass-recipe", conformingTo: .json)
}

extension NSPasteboard.PasteboardType {
  static let glassRecipe = Self(UTType.glassRecipe.identifier)
}

@MainActor
public final class DesignerController: NSObject, NSWindowDelegate {
  public let window: NSWindow
  public let canvas = GlassCanvas()
  public private(set) var parameters = GlassParameters()
  let variants = OptionBrowser(
    title: "Variants",
    options: GlassCatalog.variants,
    shortcut: "⌘L")
  let subvariants = OptionBrowser(
    title: "Subvariants", options: ["None"] + GlassCatalog.subvariants,
    shortcut: "⇧⌘L")
  private let inspector = Inspector()
  private let backdrop = BackdropView()
  let status = label("", size: 11, secondary: true)
  private let actions = ActionBindings()
  private var previewWindow: NSWindow?
  private var detachedCanvas: GlassCanvas?
  private var saveURL: URL?
  /// Readout issues currently shown in the status line.
  private var shownIssues: String?

  public override init() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1576, height: 830),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
    )
    super.init()
    window.title = "macOS Glass Designer"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    buildContent()
    canvas.movesSurfaces = true
    variants.onSelect = { [weak self] index in self?.change { $0.variant = index } }
    subvariants.onSelect = { [weak self] index in
      self?.change { $0.subvariant = index == 0 ? nil : GlassCatalog.subvariants[index - 1] }
    }
    inspector.onChange = { [weak self] mutation in self?.change(mutation) }
    inspector.onPop = { [weak self] in self?.playPop() }
    inspector.onSecondary = { [weak self] in self?.toggleSecondary() }
    canvas.onReadout = { [weak self] in self?.syncReadout() }
    sync()
  }

  public func show() {
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(variants.table)
  }

  private func button(_ title: String, action: Selector) -> NSButton {
    actionButton(title, target: self, action: action)
  }

  private func buildContent() {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let title = label("macOS Glass Designer", size: 20, weight: .semibold)
    let subtitle = label(
      "Shape the material. Copy the recipe. macOS v\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      size: 12, secondary: true)
    let presets = NSSegmentedControl(
      labels: ["Regular", "Clear", "Blur"], trackingMode: .momentary, target: nil, action: nil)
    presets.font = DesignerFont.font(size: 11)
    presets.controlSize = .regular
    actions.bind(presets) { [weak self] sender in
      let index = (sender as! NSSegmentedControl).selectedSegment
      self?.loadPreset(index)
    }
    let copy = button("Copy Swift  ⇧⌘C", action: #selector(copySwift))
    let titleRow = NSStackView(views: [title, subtitle, NSView(), status])
    titleRow.alignment = .firstBaseline
    titleRow.spacing = 12
    let listDivider = NSBox()
    listDivider.boxType = .separator
    let sidebar = vertical([variants, listDivider, subvariants], spacing: 12)
    sidebar.widthAnchor.constraint(equalToConstant: 205).isActive = true
    variants.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
    listDivider.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
    subvariants.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
    variants.heightAnchor.constraint(equalTo: subvariants.heightAnchor).isActive = true

    let stage = NSView()
    pin(backdrop, to: stage)
    pin(canvas, to: stage)
    stage.wantsLayer = true
    stage.layer?.cornerRadius = 14
    stage.layer?.masksToBounds = true
    let stageControls = buildStageControls()
    let tools = NSStackView(views: [
      presets,
      button("Pop  ⌘P", action: #selector(playPop)),
      button("Second Surface  ⌘T", action: #selector(toggleSecondary)),
      button("Detach  ⌘D", action: #selector(detachPreview)),
      NSView(),
      button("Open…", action: #selector(openRecipe)),
      button("Save…", action: #selector(saveRecipe)),
      button("Paste recipe", action: #selector(pasteRecipe)),
      button("Copy JSON", action: #selector(copyJSON)), copy,
    ])
    tools.spacing = 10
    tools.distribution = .fill
    status.lineBreakMode = .byTruncatingTail
    let header = vertical([titleRow, tools], spacing: 8)
    for view in [titleRow, tools] {
      view.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
    }
    let stageColumn = vertical([stageControls, stage], spacing: 12)
    stage.widthAnchor.constraint(equalTo: stageColumn.widthAnchor).isActive = true
    stage.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
    stage.heightAnchor.constraint(greaterThanOrEqualToConstant: 500).isActive = true
    inspector.widthAnchor.constraint(equalToConstant: 429).isActive = true
    let columns = NSStackView(views: [sidebar, stageColumn, inspector])
    columns.orientation = .horizontal
    columns.distribution = .fill
    columns.alignment = .top
    columns.spacing = 18
    for view in [sidebar, stageColumn, inspector] {
      view.heightAnchor.constraint(equalTo: columns.heightAnchor).isActive = true
    }
    let separator = NSBox()
    separator.boxType = .separator
    let root = vertical([header, separator, columns], spacing: 14)
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 14, right: 18)
    let content = NSView()
    window.contentView = content
    pin(root, to: content)
    for view in [header, separator, columns] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36).isActive = true
    }
    variants.table.nextKeyView = subvariants.table
    window.initialFirstResponder = variants.table
  }

  /// Scene, theme, and wallpaper of the screen behind the embedded glass; not part of the recipe.
  private func buildStageControls() -> NSView {
    func segmented(_ labels: [String]) -> NSSegmentedControl {
      let control = NSSegmentedControl(
        labels: labels, trackingMode: .selectOne, target: nil, action: nil)
      control.controlSize = .small
      control.font = DesignerFont.font(size: 10)
      return control
    }
    let scenes = segmented(BackdropScene.allCases.map(\.title))
    let themes = segmented(BackdropTheme.allCases.map(\.title))
    let wallpapers = NSPopUpButton(frame: .zero, pullsDown: false)
    wallpapers.controlSize = .small
    wallpapers.font = DesignerFont.font(size: 10)
    wallpapers.setAccessibilityLabel("Wallpaper")
    let installed = backdrop.installedWallpapers
    wallpapers.addItems(withTitles: installed.map(\.name))
    backdrop.onIssue = { [weak self] in self?.showStatus($0) }
    // Start from what the screen shows now: the current desktop picture and system appearance.
    backdrop.wallpaper = installed.first
    backdrop.theme =
      NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? .dark : .light
    scenes.selectedSegment = backdrop.scene.rawValue
    themes.selectedSegment = backdrop.theme.rawValue
    wallpapers.isEnabled = backdrop.scene.showsWallpaper
    actions.bind(scenes) { [weak self] sender in
      guard let self,
        let scene = BackdropScene(rawValue: (sender as! NSSegmentedControl).selectedSegment)
      else { return }
      backdrop.scene = scene
      wallpapers.isEnabled = scene.showsWallpaper
    }
    actions.bind(themes) { [weak self] sender in
      guard let theme = BackdropTheme(rawValue: (sender as! NSSegmentedControl).selectedSegment)
      else { return }
      self?.backdrop.theme = theme
    }
    actions.bind(wallpapers) { [weak self] sender in
      let index = (sender as! NSPopUpButton).indexOfSelectedItem
      guard installed.indices.contains(index) else { return }
      self?.backdrop.wallpaper = installed[index]
    }
    let row = NSStackView(views: [scenes, themes, wallpapers])
    row.spacing = 10
    row.alignment = .centerY
    return row
  }

  func change(_ mutation: (inout GlassParameters) -> Void) {
    var next = parameters
    mutation(&next)
    do {
      try next.validate()
      parameters = next
      sync()
      showStatus("")
    } catch {
      showStatus(error.localizedDescription)
      inspector.sync(parameters, canvas: canvas)
    }
  }

  func loadPreset(_ index: Int) {
    parameters = GlassParameters()
    if index == 1 { parameters.variant = 2 }
    if index == 2 {
      parameters.haloEnabled = true
    }
    sync()
    showStatus("")
  }

  private func sync() {
    do {
      try canvas.update(parameters)
      try detachedCanvas?.update(parameters)
      resizeDetached()
      variants.select(parameters.variant)
      subvariants.select(
        parameters.subvariant.flatMap { GlassCatalog.subvariants.firstIndex(of: $0) }.map { $0 + 1 }
          ?? 0)
      inspector.sync(parameters, canvas: canvas)
    } catch { showStatus(error.localizedDescription) }
  }

  private func syncReadout() {
    inspector.sync(parameters, canvas: canvas)
    let issues = (canvas.issues + (detachedCanvas?.issues ?? [])).joined(separator: " · ")
    if !issues.isEmpty {
      showStatus(issues)
      shownIssues = issues
    } else if let shownIssues {
      // Resolved issues leave the status line, unless a newer message already replaced them.
      if status.stringValue == shownIssues { showStatus("") }
      self.shownIssues = nil
    }
  }

  /// The status line truncates; its tooltip carries the full message.
  private func showStatus(_ message: String) {
    status.stringValue = message
    status.toolTip = message.isEmpty ? nil : message
  }

  @objc public func copySwift() { writeSwift(to: .general) }

  func writeSwift(to pasteboard: NSPasteboard) {
    do {
      canvas.refreshInternals()
      let swift = try SwiftExport.source(
        for: parameters, nativeFilterInputs: canvas.nativeFilterInputs)
      let json = try GlassDocument(parameters: parameters).data()
      pasteboard.clearContents()
      guard pasteboard.setString(swift, forType: .string),
        pasteboard.setData(json, forType: .glassRecipe)
      else {
        throw RecipeError.invalid("Unable to write to clipboard")
      }
      showStatus(
        "Copied Swift parameters · exact values, API mapping, and native readouts")
    } catch { showStatus(error.localizedDescription) }
  }

  @objc public func copyJSON() {
    do {
      let data = try GlassDocument(parameters: parameters).data()
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
      else {
        throw RecipeError.invalid("Unable to write to clipboard")
      }
      showStatus("Copied recipe JSON")
    } catch { showStatus(error.localizedDescription) }
  }

  @objc public func pasteRecipe() {
    guard
      let data = NSPasteboard.general.data(forType: .glassRecipe)
        ?? NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
    else {
      showStatus("Clipboard has no recipe")
      return
    }
    importData(data)
  }

  @discardableResult func importData(_ data: Data) -> Bool {
    do {
      let document = try GlassDocument.load(data)
      parameters = document.parameters
      sync()
      showStatus("Recipe loaded")
      return true
    } catch {
      showStatus("Recipe unchanged: \(error.localizedDescription)")
      return false
    }
  }

  @objc public func openRecipe() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: window) { [weak self] response in
      MainActor.assumeIsolated {
        guard response == .OK, let self, let url = panel.url else { return }
        do { if self.importData(try Data(contentsOf: url)) { self.saveURL = url } } catch {
          self.showStatus(error.localizedDescription)
        }
      }
    }
  }

  @objc public func saveRecipe() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = saveURL?.lastPathComponent ?? "Glass Recipe.json"
    panel.beginSheetModal(for: window) { [weak self] response in
      MainActor.assumeIsolated {
        guard response == .OK, let self, let url = panel.url else { return }
        do {
          try GlassDocument(parameters: self.parameters).data().write(to: url, options: .atomic)
          self.saveURL = url
          self.showStatus("Saved \(url.lastPathComponent)")
        } catch { self.showStatus(error.localizedDescription) }
      }
    }
  }

  @objc public func playPop() {
    canvas.pop()
    detachedCanvas?.pop()
  }
  @objc public func toggleSecondary() {
    canvas.toggleSecondary()
    detachedCanvas?.toggleSecondary()
    resizeDetached()
    inspector.sync(parameters, canvas: canvas)
  }
  @objc public func focusVariants() {
    window.makeKeyAndOrderFront(nil)
    variants.focus()
  }
  @objc public func focusSubvariants() {
    window.makeKeyAndOrderFront(nil)
    subvariants.focus()
  }
  @objc public func inspectorTab(_ item: NSMenuItem) { inspector.selectTab(item.tag) }

  @objc public func detachPreview() {
    if let previewWindow {
      previewWindow.orderOut(nil)
      self.previewWindow = nil
      detachedCanvas = nil
      showStatus("")
      return
    }
    let preview = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 700, height: 520),
      styleMask: [.borderless], backing: .buffered, defer: false)
    preview.title = "Glass desktop preview"
    preview.isOpaque = false
    preview.backgroundColor = .clear
    preview.isMovableByWindowBackground = true
    // A transparent window is click-through wherever its pixels are clear, including over glass,
    // so clicks would reach the window below instead of starting a drag. Take every click.
    preview.ignoresMouseEvents = false
    preview.isReleasedWhenClosed = false
    preview.level = .floating
    preview.hidesOnDeactivate = false
    preview.delegate = self
    let canvas = GlassCanvas()
    if self.canvas.secondaryVisible { canvas.toggleSecondary() }
    preview.contentView = canvas
    detachedCanvas = canvas
    previewWindow = preview
    canvas.onReadout = { [weak self] in self?.syncReadout() }
    sync()
    preview.center()
    preview.orderFront(nil)
    window.makeKeyAndOrderFront(nil)
    showStatus("Drag the desktop preview over other windows · ⌘D closes it")
  }

  private func resizeDetached() {
    guard let previewWindow else { return }
    let style: NSWindow.StyleMask = parameters.windowTitled ? [.titled, .closable] : [.borderless]
    if previewWindow.styleMask != style { previewWindow.styleMask = style }
    let margin = max(
      parameters.haloEnabled ? parameters.haloMargin : 0,
      parameters.customShadow
        ? parameters.shadowRadius * 2
          + max(abs(parameters.shadowOffsetX), abs(parameters.shadowOffsetY)) : 16
    ).rounded(.up)
    let secondary = canvas.secondaryVisible ? 80 + parameters.panelGap : 0
    // The main surface stays centered; reserve the same headroom above and below it.
    previewWindow.setContentSize(
      NSSize(
        width: parameters.width + margin * 2, height: parameters.height + margin * 2 + secondary * 2
      ))
    previewWindow.invalidateShadow()
  }

  public func windowWillClose(_ notification: Notification) {
    previewWindow?.orderOut(nil)
    previewWindow = nil
    detachedCanvas = nil
  }
}

@MainActor
public final class DesignerAppDelegate: NSObject, NSApplicationDelegate {
  private var controller: DesignerController?
  public func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = DesignerController()
    self.controller = controller
    buildMenu(controller)
    controller.show()
    NSApp.activate()
  }
  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func buildMenu(_ controller: DesignerController) {
    let main = NSMenu()
    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      let menu = NSMenu(title: title)
      item.submenu = menu
      main.addItem(item)
      return menu
    }
    func item(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
      modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil
    ) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = target ?? controller
      menu.addItem(item)
    }
    let app = menu("Glass Designer")
    item(app, "Quit Glass Designer", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
    let file = menu("File")
    item(file, "Open Recipe…", #selector(DesignerController.openRecipe), "o")
    item(file, "Save Recipe…", #selector(DesignerController.saveRecipe), "s")
    item(file, "Close", #selector(NSWindow.performClose(_:)), "w", target: controller.window)
    let edit = menu("Edit")
    for (title, selector, key) in [
      ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
      ("Select All", "selectAll:", "a"),
    ] {
      let entry = NSMenuItem(
        title: title, action: NSSelectorFromString(selector), keyEquivalent: key)
      edit.addItem(entry)
    }
    edit.addItem(.separator())
    item(
      edit, "Copy Swift Parameters", #selector(DesignerController.copySwift), "c",
      modifiers: [.command, .shift])
    item(
      edit, "Paste Recipe", #selector(DesignerController.pasteRecipe), "v",
      modifiers: [.command, .shift])
    let view = menu("View")
    item(view, "Focus Variants", #selector(DesignerController.focusVariants), "l")
    item(
      view, "Focus Subvariants", #selector(DesignerController.focusSubvariants), "l",
      modifiers: [.command, .shift])
    for (index, name) in ["Surface", "Blur", "Shadow", "Filter", "Rim", "Motion"].enumerated() {
      let entry = NSMenuItem(
        title: name + " Inspector", action: #selector(DesignerController.inspectorTab(_:)),
        keyEquivalent: String(index + 1))
      entry.target = controller
      entry.tag = index
      view.addItem(entry)
    }
    view.addItem(.separator())
    item(view, "Toggle Desktop Preview", #selector(DesignerController.detachPreview), "d")
    item(view, "Play Pop", #selector(DesignerController.playPop), "p")
    item(view, "Toggle Second Surface", #selector(DesignerController.toggleSecondary), "t")
    NSApp.mainMenu = main
  }
}
