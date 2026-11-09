import AppKit

/// A link to a web page, in the link color, opened in the browser; the pointer turns to a hand over it.
final class LinkButton: NSButton {
    private var url: URL?

    static func make(_ title: String, address: String, size: CGFloat = 13) -> LinkButton {
        let button = LinkButton(frame: .zero)
        button.url = URL(string: address)
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
        ])
        button.toolTip = address
        button.target = button
        button.action = #selector(openLink)
        button.setAccessibilityRole(.link)
        return button
    }

    @objc private func openLink() {
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
