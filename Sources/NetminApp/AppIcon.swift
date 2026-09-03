import AppKit

enum AppIcon {
    static func make(size: CGFloat = 128) -> NSImage {
        // Use the original bundled icon for shipped builds and previews that include resources.
        if let url = AppResources.resourcesURL?.appendingPathComponent("NetminIcon.icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // Keep a development fallback for isolated source fixtures without bundled resources.
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                     xRadius: size * 0.23, yRadius: size * 0.23).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: "Netmin")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "Netmin")!
        symbol.draw(in: NSRect(x: size * 0.24, y: size * 0.24, width: size * 0.52, height: size * 0.52))
        image.unlockFocus()
        return image
    }
}
