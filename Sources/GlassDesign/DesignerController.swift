import AppKit
import UniformTypeIdentifiers

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
  private let status = label("", size: 11, secondary: true)
  private var targets: [ActionTarget] = []
  private var previewWindow: NSWindow?
  private var detachedCanvas: GlassCanvas?
  private var saveURL: URL?

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

  private func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
    let target = ActionTarget(handler)
    targets.append(target)
    control.target = target
    control.action = #selector(ActionTarget.fire(_:))
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
    bind(presets) { [weak self] sender in
      let index = (sender as! NSSegmentedControl).selectedSegment
      self?.loadPreset(index)
    }
    let copy = button("Copy Swift  ⇧⌘C", action: #selector(copySwift))
    copy.hasDestructiveAction = false
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
    let backgrounds = NSSegmentedControl(
      labels: ["Landscape", "Light", "Dark", "Text"], trackingMode: .selectOne, target: nil,
      action: nil)
    backgrounds.controlSize = .small
    backgrounds.font = DesignerFont.font(size: 10)
    backgrounds.selectedSegment = 0
    bind(backgrounds) { [weak self] sender in
      self?.backdrop.mode = (sender as! NSSegmentedControl).selectedSegment
    }
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
    let stageColumn = vertical([backgrounds, stage], spacing: 12)
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

  func change(_ mutation: (inout GlassParameters) -> Void) {
    var next = parameters
    mutation(&next)
    do {
      try next.validate()
      parameters = next
      sync()
      status.stringValue = ""
    } catch {
      status.stringValue = error.localizedDescription
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
    status.stringValue = ""
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
    } catch { status.stringValue = error.localizedDescription }
  }

  private func syncReadout() {
    inspector.sync(parameters, canvas: canvas)
    let allIssues = canvas.issues + (detachedCanvas?.issues ?? [])
    if !allIssues.isEmpty {
      status.stringValue = allIssues.joined(separator: " · ")
      status.toolTip = status.stringValue
    }
  }

  @objc public func copySwift() { writeSwift(to: .general) }

  func writeSwift(to pasteboard: NSPasteboard) {
    do {
      canvas.refreshInternals()
      let swift = try SwiftExport.source(for: parameters, observed: canvas.observed)
      let json = try GlassDocument(parameters: parameters).data()
      pasteboard.clearContents()
      guard pasteboard.setString(swift, forType: .string),
        pasteboard.setData(json, forType: .init("com.alexgorbatchev.glass-recipe"))
      else {
        throw RecipeError.invalid("Unable to write to clipboard")
      }
      status.stringValue =
        "Copied Swift parameters · exact values, API mapping, and native readouts"
    } catch { status.stringValue = error.localizedDescription }
  }

  @objc public func copyJSON() {
    do {
      let data = try GlassDocument(parameters: parameters).data()
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
      else {
        throw RecipeError.invalid("Unable to write to clipboard")
      }
      status.stringValue = "Copied recipe JSON"
    } catch { status.stringValue = error.localizedDescription }
  }

  @objc public func pasteRecipe() {
    guard
      let data = NSPasteboard.general.data(forType: .init("com.alexgorbatchev.glass-recipe"))
        ?? NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
    else {
      status.stringValue = "Clipboard has no recipe"
      return
    }
    importData(data)
  }

  @discardableResult func importData(_ data: Data) -> Bool {
    do {
      let document = try GlassDocument.load(data)
      parameters = document.parameters
      sync()
      status.stringValue = "Recipe loaded"
      return true
    } catch {
      status.stringValue = "Recipe unchanged: \(error.localizedDescription)"
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
          self.status.stringValue = error.localizedDescription
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
          self.status.stringValue = "Saved \(url.lastPathComponent)"
        } catch { self.status.stringValue = error.localizedDescription }
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
      status.stringValue = ""
      return
    }
    let preview = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 700, height: 520),
      styleMask: [.borderless], backing: .buffered, defer: false)
    preview.title = "Glass desktop preview"
    preview.isOpaque = false
    preview.backgroundColor = .clear
    preview.isMovableByWindowBackground = true
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
    status.stringValue = "Drag the desktop preview over other windows · ⌘D closes it"
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
