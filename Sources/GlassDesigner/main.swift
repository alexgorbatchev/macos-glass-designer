import AppKit
import GlassDesign

// The application delegate owns all windows for the process lifetime.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = DesignerAppDelegate()
app.delegate = delegate
app.run()
