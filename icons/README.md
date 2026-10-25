# PlainVoice — Voice Ribbon icons

The glossy app icon and the line-art menu bar ribbon, packaged as macOS assets. The app name is used only for filenames; no text appears in the artwork.

## Xcode

1. Drag `AppIcon.appiconset` and `MenuBarIcon.imageset` from the included `Assets.xcassets` into your project's existing asset catalog. Replace an existing AppIcon set if needed; don't add a second catalog containing duplicate asset names.
2. In the app target, select `AppIcon` as the App Icon asset.
3. Use `MenuBarIcon` for the status item. The included asset metadata marks it as a template, which lets macOS choose its color for light/dark appearances.

```swift
let image = NSImage(named: "MenuBarIcon")!
image.isTemplate = true
image.size = NSSize(width: 30, height: 20)
statusItem.button?.image = image
```

SwiftUI:

```swift
MenuBarExtra {
    // Your menu content
} label: {
    Image("MenuBarIcon").renderingMode(.template)
}
```

## Files

- `PlainVoice.icns`: multi-resolution macOS icon for projects that use an ICNS resource.
- `PlainVoice-1024.png`: transparent 1024 px app icon master.
- `PlainVoice.iconset`: standard PNG size set used to build the ICNS.
- `Assets.xcassets`: AppIcon and template menu bar assets, with JSON metadata.
- `MenuBar`: transparent black template PNGs and white fallback PNGs at 1x, 2x and 3x. Logical canvas is 30×20 pt. Use the template asset in a native app; white copies are for manually managed appearances.
- `MenuBar/MenuBarIcon-Outline.png`: the supplied line-art ribbon master. `Resources/MenuBarIcon*.png` are derived from it with a slightly heavier stroke for status-bar legibility.
- `Preview.png`: visual reference only; don't use it as an app asset.
- `generation-prompts.md`: prompts used to prepare standalone artwork from the selected concept.

Apple documentation:
- https://help.apple.com/xcode/mac/current/en.lproj/dev10510b1f7.html
- https://help.apple.com/xcode/mac/current/en.lproj/dev7a4aebe73.html
- https://developer.apple.com/documentation/appkit/nsimage/istemplate

Artwork was prepared using built-in image generation, then mechanically resized and packaged. The standalone artwork may have minor rendering differences from the original concept board.
