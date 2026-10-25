import AppKit

/// The QuietSpeech ribbon mark, loaded from the supplied MenuBarIcon template
/// artwork so the menu bar, sidebar, and onboarding tile use the same drawing.
enum BrandMark {
    private static let logicalSize = NSSize(width: 30, height: 20)
    private static let template: NSImage? = loadTemplate()

    static func image() -> NSImage {
        guard let template, let copy = template.copy() as? NSImage else {
            return NSImage(size: logicalSize)
        }
        return copy
    }

    static func image(size: CGFloat) -> NSImage {
        let height = size * logicalSize.height / logicalSize.width
        guard let template, let copy = template.copy() as? NSImage else {
            return NSImage(size: NSSize(width: size, height: height))
        }
        copy.size = NSSize(width: size, height: height)
        return copy
    }

    private static func loadTemplate() -> NSImage? {
        let image = NSImage(size: logicalSize)
        var loaded = false

        for name in ["MenuBarIcon", "MenuBarIcon@2x", "MenuBarIcon@3x"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = logicalSize
            image.addRepresentation(rep)
            loaded = true
        }

        guard loaded else { return nil }
        image.isTemplate = true
        return image
    }
}
