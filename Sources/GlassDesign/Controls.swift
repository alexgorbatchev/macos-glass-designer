import AppKit

@MainActor
final class ActionTarget: NSObject {
  let handler: (NSControl) -> Void
  init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
  @objc func fire(_ sender: NSControl) { handler(sender) }
}

/// Ends a text field edit when the user presses anywhere outside the field. AppKit leaves the
/// field editing until Return, so a press elsewhere commits the typed value, except a press on a
/// slider, which discards it: the slider sets the value instead. The press reaches the window
/// before the slider starts tracking, which is why this belongs here.
@MainActor
final class DesignerWindow: NSWindow {
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown, let editor = firstResponder as? NSText,
      let field = editor.delegate as? NSTextField, let content = contentView,
      let hit = content.hitTest(
        content.superview?.convert(event.locationInWindow, from: nil) ?? .zero),
      !hit.isDescendant(of: field)
    {
      if hit is NSSlider { field.abortEditing() } else { makeFirstResponder(nil) }
    }
    super.sendEvent(event)
  }
}

/// Retains closure targets: AppKit controls reference their targets weakly.
@MainActor
final class ActionBindings {
  private var targets: [ActionTarget] = []

  func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
    let target = ActionTarget(handler)
    targets.append(target)
    control.target = target
    control.action = #selector(ActionTarget.fire(_:))
  }

  func removeAll() { targets.removeAll() }
}

@MainActor
func label(
  _ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
  secondary: Bool = false
) -> NSTextField {
  let view = NSTextField(labelWithString: text)
  view.font = DesignerFont.font(size: size, weight: weight)
  view.textColor = secondary ? .secondaryLabelColor : .labelColor
  return view
}

@MainActor
func actionButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
  let button = NSButton(title: title, target: target, action: action)
  button.font = DesignerFont.font(size: 11)
  button.bezelStyle = .rounded
  // Maple Mono sits one point low in AppKit's native push-button title layout.
  let text = NSMutableAttributedString(attributedString: button.attributedTitle)
  text.addAttribute(.baselineOffset, value: 1, range: NSRange(location: 0, length: text.length))
  if let start = title.firstIndex(where: { "⌃⌥⇧⌘".contains($0) }) {
    text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
      range: NSRange(start..<title.endIndex, in: title))
  }
  button.attributedTitle = text
  return button
}

@MainActor
func vertical(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
  let stack = NSStackView(views: views)
  stack.orientation = .vertical
  stack.alignment = .leading
  stack.spacing = spacing
  return stack
}

@MainActor
func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
  child.translatesAutoresizingMaskIntoConstraints = false
  parent.addSubview(child)
  NSLayoutConstraint.activate([
    child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
    child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
    child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
    child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
  ])
}

@MainActor
private final class OptionRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    let color = isEmphasized
      ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
  }
}

/// Native selection notifications apply values for both mouse and keyboard, without confirmation.
@MainActor
final class OptionBrowser: NSView, NSTableViewDataSource, NSTableViewDelegate {
  let table = NSTableView()
  private let options: [String]
  private let displayNames: [String]
  private var syncing = false
  var onSelect: ((Int) -> Void)?

  init(title: String, options: [String], shortcut: String) {
    self.options = options
    displayNames = options.map { name in
      let prefix = name.hasPrefix("iOS") ? "iOS " : ""
      let body = prefix.isEmpty ? name : String(name.dropFirst(3))
      return prefix + body.replacingOccurrences(
        of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }
    super.init(frame: .zero)
    let scroll = NSScrollView()
    table.addTableColumn(NSTableColumn(identifier: .init("name")))
    table.headerView = nil
    table.style = .plain
    table.intercellSpacing = NSSize(width: 0, height: 2)
    table.rowHeight = 25
    table.allowsEmptySelection = false
    table.allowsMultipleSelection = false
    table.allowsTypeSelect = true
    table.dataSource = self
    table.delegate = self
    table.setAccessibilityLabel(title)
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    let header = NSStackView(views: [
      label(title.uppercased(), size: 10, weight: .semibold, secondary: true),
      NSView(), label(shortcut, size: 10, secondary: true),
    ])
    header.alignment = .centerY
    let stack = vertical([header, scroll], spacing: 8)
    pin(stack, to: self)
    header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
  }
  required init?(coder: NSCoder) { nil }
  func select(_ row: Int) {
    guard options.indices.contains(row) else { return }
    guard table.selectedRow != row else { return }
    syncing = true
    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    table.scrollRowToVisible(row)
    syncing = false
  }
  func focus() { window?.makeFirstResponder(table) }
  func numberOfRows(in tableView: NSTableView) -> Int { options.count }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let identifier = NSUserInterfaceItemIdentifier("optionRow")
    let view = tableView.makeView(withIdentifier: identifier, owner: self) as? OptionRowView
      ?? OptionRowView()
    view.identifier = identifier
    return view
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let identifier = NSUserInterfaceItemIdentifier("option")
    let cell =
      table.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
      ?? NSTableCellView()
    if cell.textField == nil {
      let text = label("")
      text.lineBreakMode = .byTruncatingTail
      text.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(text)
      NSLayoutConstraint.activate([
        text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
        text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
        text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
      cell.textField = text
      cell.identifier = identifier
    }
    cell.textField?.stringValue = displayNames[row]
    cell.toolTip = options[row]
    return cell
  }
  func tableView(
    _ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int
  ) -> String? {
    displayNames[row]
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !syncing, options.indices.contains(table.selectedRow) else { return }
    table.scrollRowToVisible(table.selectedRow)
    onSelect?(table.selectedRow)
  }
}
