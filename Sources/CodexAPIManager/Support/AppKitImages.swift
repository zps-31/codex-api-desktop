import AppKit

extension NSImage {
    static func safeSystemSymbol(
        _ name: String,
        accessibilityDescription: String?
    ) -> NSImage {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
