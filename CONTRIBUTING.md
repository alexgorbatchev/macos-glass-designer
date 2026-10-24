---
created_on: 2026-10-23 12:00
last_modified: 2026-10-23 12:47
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

`just check` runs tests and bundles a release build. Swift and Objective-C warnings are errors. `just run` bundles and opens the app; it stays open until its last main window closes. `just run-ai` opens the same GUI with `AGENT=1`; there is no text-mode interface.

`just capture` creates and closes its own native test window and captures all six inspectors under `.tmp/verification/`. Screen Recording permission for the invoking terminal is required for captures; the regular tests do not capture the screen. View bitmap caching does not capture compositor glass, so visual verification uses window screenshots.

## Structure and contracts

- `Sources/GlassDesign/GlassParameters.swift` is the Codable recipe. `GlassCatalog.swift` defines known controls and ranges. Update validation and export tests with any recipe change.
- `GlassCanvas.swift` owns native glass, halo, shadows, and frame animations. AppKit work stays on the main actor.
- `PrivateGlass.swift` and `Sources/GlassBridge/` isolate undocumented hooks. The Objective-C bridge catches KVC exceptions, checks runtime availability, and reports failures. Keep private enumeration values restricted to the inspected OS contract; some invalid integers trap within AppKit.
- `Inspector.swift` supplies the six inspectors. Native table selection notifications in `Controls.swift` apply variants immediately. Preserve keyboard focus during preview updates; selection must never require Enter.
- `CurveEditor.swift` edits the ordered cubic segments in `HaloCurve.swift`. Double-click inserts points; dragging and keyboard actions update the recipe and native mask immediately. Curve coordinates use normalized distance and strength. Recipe schema 2 stores all anchors and handles.
- `DesignerFont.swift` registers bundled Maple Mono fonts for this process. The signed app must include the SwiftPM resource bundle under `Contents/Resources`; preserve the font license alongside the font files.
- `SwiftExport.swift` exports a standalone Swift value specification with API notes. Do not round numbers or replace chosen colors with a hardcoded color. Swift clipboard output includes a custom JSON pasteboard representation for round-trip use.
- Removing a filter/rim override must rebuild the **container**, not just its glass children: the combined filter belongs to the container and retains overrides otherwise. Native tests exercise restoration.
- Animated halo, fills, and shadow geometry follow native frame-change notifications. Parameter edits during motion rebuild the animated recipe; stale completions must not alter the replacement.
- Corner-radius changes invalidate the native container subtree so its SDF geometry updates during slider tracking. Deferred native overrides run in common run-loop modes so filter and halo updates do not wait for mouse release.

## Verification

Use red/green development, including native tests for rendering, clipboard, or keyboard behavior. Temporarily remove the implementation change and require the relevant regression test to fail, then restore it and rerun the suite. Native tests create their own windows and exit; do not substitute static configuration assertions for behavior.

The test writes a standalone export to `.tmp/verification/DesignedGlass.swift`. Check that artifact with:

```sh
xcrun swiftc -warnings-as-errors -typecheck .tmp/verification/DesignedGlass.swift
```

Keep screenshots, temporary probes, and logs in `.tmp/`, and generated bundles in `dist/`. Use `.workspaces/` for worktrees. Do not use heredocs. Inspect code with codegraph or `rg` and read applicable skills before modifying code. Changes to sibling projects are outside this app's scope.

Do not introduce simulated glass, compatibility fallback materials, extra GUI frameworks, or silent ignored settings. Do not publish releases, tags, or packages without explicit user authorization. Never commit credentials or private internal domains to GitHub.
