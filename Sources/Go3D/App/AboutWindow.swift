import AppKit

/// The About window: what the game is, who made it and where to find him, in the game's language. Return or Escape
/// closes it.
final class AboutWindow: NSPanel {
    private static let profiles = [
        ("GitHub", "https://github.com/makarov-mm"),
        ("LinkedIn", "https://www.linkedin.com/in/makarov-mm/"),
        ("Threads", "https://www.threads.net/@m.m.makarov"),
        ("Instagram", "https://www.instagram.com/m.m.makarov/"),
    ]
    private static let sponsors = "https://github.com/sponsors/makarov-mm"
    private static let textWidth: CGFloat = 380

    static func make() -> AboutWindow {
        let window = AboutWindow(contentRect: NSRect(x: 0, y: 0, width: 444, height: 480), styleMask: [.titled, .closable, .fullSizeContentView],
                                 backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        return window
    }

    /// Shows the window in front, a little above the middle of the game's window the first time.
    func show(_ language: Language, over parent: NSWindow?) {
        let wasVisible = isVisible
        build(language)
        if !wasVisible {
            if let parent {
                let frame = parent.frame
                setFrameOrigin(NSPoint(x: (frame.midX - self.frame.width / 2).rounded(), y: (frame.midY - self.frame.height / 2 + frame.height * 0.08).rounded()))
            } else {
                center()
            }
        }
        makeKeyAndOrderFront(nil)
    }

    /// The texts in another language, while the window is open.
    func update(_ language: Language) {
        if isVisible {
            build(language)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    @objc private func closeWindow() {
        close()
    }

    private func build(_ language: Language) {
        func tr(_ id: Str) -> String { id.text(language) }
        title = tr(.menuAbout)

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 112), icon.heightAnchor.constraint(equalToConstant: 112)])

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let name = Self.label(tr(.title), .systemFont(ofSize: 24, weight: .bold), .labelColor)
        let versionLabel = Self.label(format(tr(.aboutVersion), version), .systemFont(ofSize: 12), .secondaryLabelColor)
        let description = Self.paragraph(tr(.aboutDescription), .systemFont(ofSize: 13), .labelColor)
        let author = Self.label(tr(.aboutAuthor), .systemFont(ofSize: 14, weight: .semibold), .labelColor)
        let linksCaption = Self.label(tr(.aboutLinks), .systemFont(ofSize: 12), .secondaryLabelColor)
        let links = NSStackView(views: Self.profiles.map { LinkButton.make($0.0, address: $0.1) })
        links.orientation = .horizontal
        links.spacing = 18
        let support = Self.paragraph(tr(.aboutSupport), .systemFont(ofSize: 12), .secondaryLabelColor)

        let heart = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemPink]))
        let sponsor = LinkButton.make("GitHub Sponsors", address: Self.sponsors)
        if let heart {
            sponsor.image = heart
            sponsor.imagePosition = .imageLeading
        }
        let license = Self.label(tr(.aboutLicense), .systemFont(ofSize: 11), .tertiaryLabelColor)
        let close = NSButton(title: tr(.aboutClose), target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\r"
        close.controlSize = .large

        let stack = NSStackView(views: [icon, name, versionLabel, description, author, linksCaption, links, support, sponsor, license, close])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(2, after: name)
        stack.setCustomSpacing(18, after: versionLabel)
        stack.setCustomSpacing(20, after: description)
        stack.setCustomSpacing(4, after: author)
        stack.setCustomSpacing(8, after: linksCaption)
        stack.setCustomSpacing(20, after: links)
        stack.setCustomSpacing(6, after: support)
        stack.setCustomSpacing(20, after: sponsor)
        stack.setCustomSpacing(16, after: license)
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 32, bottom: 22, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // The frosted background of a window.
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            description.widthAnchor.constraint(equalToConstant: Self.textWidth),
            support.widthAnchor.constraint(equalToConstant: Self.textWidth),
        ])
        let top = frame.maxY
        contentView = background
        setContentSize(stack.fittingSize)
        if isVisible {
            setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top)) // grows or shrinks downward
        }
        initialFirstResponder = close
    }

    private static func label(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        return field
    }

    private static func paragraph(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.preferredMaxLayoutWidth = textWidth
        field.isSelectable = false
        return field
    }
}
