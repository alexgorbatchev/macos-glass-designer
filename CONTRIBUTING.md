---
created_on: 2026-10-23 12:00
last_modified: 2026-10-25 20:52
status: current
---

# Developing macOS Glass Designer

For developers and agents working on this native app. Use macOS 26+, Xcode with the macOS 26 SDK, Swift 6.2+, and [just](https://just.systems). The package uses Apple frameworks and bundles unmodified Maple Mono 7.9 fonts under the SIL Open Font License. The checked environment is Swift 6.3.3 on Apple Silicon with macOS 26.6.2.

## Commands

```sh
just build
just test
just bundle
```

`just check` runs tests and bundles a release build. Swift and Objective-C warnings are errors. `just run` bundles and opens the app; it stays open until its last main window closes. There is no text-mode interface.

`just screenshot` regenerates the README screenshot, `docs/images/designer.png`, from a fixed setup: the Blur preset over the dark Desktop scene on the Sonoma wallpaper, with the Blur inspector open. Rerun it after visible UI changes. `just capture` creates and closes its own native test window and captures all six inspectors under `.tmp/verification/`. Screen Recording permission for the invoking terminal is required for captures; the regular tests do not capture the screen. View bitmap caching does not capture compositor glass, so visual verification uses window screenshots.

## Structure and contracts

- `Sources/GlassDesign/GlassParameters.swift` is the Codable recipe and `GlassDocument`, which checks `schemaVersion` before decoding the fields and reports decoding failures by field path. Bump `currentSchemaVersion` for any incompatible recipe change; older versions are rejected, not migrated. `GlassCatalog.swift` defines known controls and ranges. Update validation and export tests with any recipe change.
- `GlassCanvas.swift` owns native glass, halo, shadows, and frame animations. AppKit work stays on the main actor.
- `PrivateGlass.swift` and `Sources/GlassBridge/` isolate undocumented hooks. The Objective-C bridge catches KVC exceptions, checks runtime availability, and every read and write reports failures into the canvas issues. Keep private enumeration values restricted to the inspected OS contract; some invalid integers trap within AppKit.
- `NativeReadouts.swift` keeps AppKit's native filter and rim values per private object. Overrides overwrite those objects in place, so natives are captured before the designer's first write; a live value that differs from the last write means AppKit rebuilt the material. Readouts and the export's native comments must never report an override.
- Tint and fill colors are sRGB HSBA (`NSColor(hue:saturation:brightness:alpha:)`), matching what the export tells agents. Do not use calibrated (Generic RGB) constructors.
- `Inspector.swift` supplies the six inspectors. Native table selection notifications in `Controls.swift` apply variants immediately; `ActionBindings` retains closure targets for controls. Preserve keyboard focus during preview updates; selection must never require Enter.
- `CurveEditor.swift` edits the ordered cubic segments in `HaloCurve.swift`; the Blur inspector adds its toolbar. Keyboard input goes through `interpretKeyEvents` and AppKit's standard responder actions (`moveLeft:`, `insertTab:`, `deleteBackward:`, …), never raw key codes. `menu(for:)` supplies the point and curve context menus. Dragging, menus, and keyboard actions update the recipe and native mask immediately. Curve coordinates use normalized distance and strength. `HaloCurve` enforces point kinds: smooth handles stay on one line, symmetric handles also match in length, endpoints are corners, and a constrained handle shortens along its line rather than leaving its segment or the unit square. Recipe schema 3 stores all anchors, handles, and point kinds.
- `HaloMask.swift` draws the blur mask as an alpha-only image with Core Graphics gradients (interior, four edges, four corners). The `variableBlur` filter and layer masks read alpha. The mask is rebuilt on every frame of a second-surface animation, so keep it well under a frame; the native test prints the worst-case timing.
- `BackdropView.swift` is the stage behind the embedded glass; `BackdropScenes.swift` and `BackdropCode.swift` draw its Desktop, Article, Code, and Photos scenes. Scenes use AppKit semantic colors under the backdrop's `NSAppearance` (and Xcode's default syntax palettes), never fixed light or dark fills. `Wallpapers.swift` lists installed wallpapers, picks a dynamic wallpaper's light or dark image from its `apple_desktop:apr` metadata, and downsamples with ImageIO off the main thread; only the wallpaper on screen stays cached at full size. Nothing is bundled.
- `DesignerFont.swift` registers bundled Maple Mono fonts for this process. The signed app must include the SwiftPM resource bundle under `Contents/Resources`; preserve the font license alongside the font files.
- `SwiftExport.swift` exports a standalone Swift value specification with API notes. Do not round numbers or replace chosen colors with a hardcoded color. Swift clipboard output includes a JSON representation under the `UTType.glassRecipe` pasteboard type, an exported UTI declared in `Resources/Info.plist`.
- Removing a filter/rim override must rebuild the **container**, not just its glass children: the combined filter belongs to the container and retains overrides otherwise. Native tests exercise restoration.
- Dragging the embedded glass moves it over the scene (`GlassCanvas.movesSurfaces`). The canvas takes every press on the stage, so the glass and sample text never swallow one, and keeps the glass and an open second surface inside the stage. The position is preview-only and never enters the recipe. The detached canvas leaves this off, so a drag moves its window.
- The detached preview is a transparent window, which the window server makes click-through wherever its pixels are clear, glass included. It sets `ignoresMouseEvents = false` so every click reaches it and `isMovableByWindowBackground` can drag it.
- Animated halo, fills, and shadow geometry follow native frame-change notifications. Parameter edits during motion rebuild the animated recipe; stale completions must not alter the replacement.
- Corner-radius changes invalidate the native container subtree so its SDF geometry updates during slider tracking. Deferred native overrides run in common run-loop modes so filter and halo updates do not wait for mouse release.

## Verification

Use red/green development, including native tests for rendering, clipboard, or keyboard behavior. Temporarily remove the implementation change and require the relevant regression test to fail, then restore it and rerun the suite. Native tests create their own windows and exit; do not substitute static configuration assertions for behavior. AppKit builds layers and runs animations asynchronously, so tests wait for the actual condition with `waitUntil` from `Tests/GlassDesignTests/TestSupport.swift`, never a fixed delay.

Tests write standalone exports to `.tmp/verification/` and typecheck each one with `xcrun swiftc -warnings-as-errors -typecheck`; a failure prints the compiler diagnostics.

Keep screenshots, temporary probes, and logs in `.tmp/`, and generated bundles in `dist/`. Use `.workspaces/` for worktrees. Do not use heredocs. Inspect code with codegraph or `rg` and read applicable skills before modifying code. Changes to sibling projects are outside this app's scope.

Do not introduce simulated glass, compatibility fallback materials, extra GUI frameworks, or silent ignored settings. Do not publish releases, tags, or packages without explicit user authorization. Never commit credentials or private internal domains to GitHub.
