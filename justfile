default:
    @just --list

# Build the native application with warnings treated as errors.
build:
    swift build -Xswiftc -warnings-as-errors -Xcc -Werror

# Exercise recipes, clipboard output, keyboard navigation, and native rendering.
test:
    swift test -Xswiftc -warnings-as-errors -Xcc -Werror

# Create an ad-hoc-signed local application bundle.
bundle:
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release -Xswiftc -warnings-as-errors -Xcc -Werror
    binary_dir="$(swift build -c release --show-bin-path)"
    app_dir="$PWD/dist/macOS Glass Designer.app"
    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
    cp "$binary_dir/macos-glass-designer" "$app_dir/Contents/MacOS/macos-glass-designer"
    cp Resources/Info.plist "$app_dir/Contents/Info.plist"
    cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
    cp -R "$binary_dir/macos-glass-designer_GlassDesign.bundle" "$app_dir/Contents/Resources/"
    plutil -lint "$app_dir/Contents/Info.plist"
    codesign --force --sign - "$app_dir"
    codesign --verify --strict "$app_dir"
    # Notify Launch Services that the rebuilt bundle and its icon have changed.
    touch "$app_dir"
    printf '%s\n' "$app_dir"

# Open the application; closing its last main window quits it.
run: bundle
    open "dist/macOS Glass Designer.app"

# Capture each inspector in a self-exiting test window (Screen Recording permission required).
capture:
    GLASS_CAPTURE=1 swift test -Xswiftc -warnings-as-errors -Xcc -Werror --filter NativeTests/testNativeRenderingAndLayoutAcrossInspectors

# Capture the README screenshot into docs/images (Screen Recording permission required).
screenshot:
    mkdir -p docs/images
    GLASS_SCREENSHOT="$PWD/docs/images/designer.png" swift test -Xswiftc -warnings-as-errors -Xcc -Werror --filter ScreenshotTests
    sips -Z 1600 docs/images/designer.png > /dev/null

check: test bundle
