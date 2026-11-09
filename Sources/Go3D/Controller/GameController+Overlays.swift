import Foundation

// What shows over the board: the help, the banner at the end of a game, and the toasts; and the texts they share
// with the panel.
extension GameController {
    static let helpRows = 13 // in the left column; the right one has a row less
    static let helpWidth: Float = 880
    static let helpRow: Float = 26
    static let helpPad: Float = 28

    /// The keys and what they do, the left column first.
    private var helpLines: [(keys: String, action: Str)] {
        [
            (tr(.keyClick), .helpClick),
            (tr(.keyDrag), .helpRotate),
            (tr(.keyWheel), .helpZoom),
            ("⌘Z  ←  ⌫", .helpUndo),
            ("⇧⌘Z  →", .helpRedo),
            ("P", .helpPass),
            ("H", .helpHint),
            ("E", .helpEstimate),
            ("↩", .helpAccept),
            ("N", .helpNew),
            ("⌘C", .helpCopy),
            ("⌘V", .helpPaste),
            ("A", .helpAbout),
            ("F", .helpFlip),
            ("V", .helpTopView),
            ("1 – 5", .helpLevel),
            ("M", .helpMode),
            ("B", .helpBoard),
            ("C", .helpCoordinates),
            ("T", .helpTheme),
            ("S", .helpSound),
            ("L", .helpLanguage),
            ("Tab", .helpPanel),
            ("⌃⌘F", .helpFullScreen),
            ("Esc  ?", .helpClose),
        ]
    }

    private var helpCardWidth: Float { min(Self.helpWidth * scale, freeArea.width - 20 * scale) }

    /// The rules note in lines that fit the help.
    func rulesLines() -> [String] {
        let width = helpCardWidth - 2 * Self.helpPad * scale
        var lines: [String] = []
        var line = ""
        for word in tr(.rulesNote).split(separator: " ") {
            let longer = line.isEmpty ? String(word) : line + " " + word
            if !line.isEmpty && painter.measure(.body, longer) > width {
                lines.append(line)
                line = String(word)
            } else {
                line = longer
            }
        }
        if !line.isEmpty {
            lines.append(line)
        }
        return lines
    }

    func helpCard(lines: Int) -> UiRect {
        let rows = Float(Self.helpRows + 1 + lines)
        let free = freeArea
        let width = helpCardWidth
        let height = (2 * Self.helpPad + 44 + 12 + rows * Self.helpRow) * scale
        return UiRect(x: free.x + (free.width - width) / 2, y: max(10 * scale, (Float(pixelHeight) - height) / 2), width: width, height: height)
    }

    var bannerCard: UiRect {
        let width = max(painter.measure(.display, bannerTitle) + 80 * scale, painter.measure(.body, bannerDetail) + 60 * scale, 320 * scale)
        let free = freeArea
        return UiRect(x: free.x + (free.width - width) / 2, y: 26 * scale - (1 - bannerFade) * 20 * scale, width: width, height: 92 * scale)
    }

    // MARK: Drawing

    /// The winner and how, at the top, once the stones have settled.
    func drawBanner() {
        guard bannerFade > 0.001 else { return }
        let p = painter
        let card = bannerCard
        p.shadow(card, blur: 24 * scale, UiColor(0, 0, 0, 120).faded(bannerFade))
        p.fill(card, radius: 18 * scale, UiColor(14, 16, 24, 150).faded(bannerFade))
        p.outline(card, radius: 18 * scale, accentColor.faded(0.6 * bannerFade))
        p.textCentered(.display, UiRect(x: card.x, y: card.y + 8 * scale, width: card.width, height: 48 * scale), bannerTitle,
                       UiPalette.text.faded(bannerFade))
        p.textCentered(.body, UiRect(x: card.x, y: card.y + 54 * scale, width: card.width, height: 26 * scale), bannerDetail,
                       UiPalette.muted.faded(bannerFade))
    }

    /// The keys, in two columns, and the rules; a click outside closes it.
    func drawHelp() {
        let p = painter
        p.fill(UiRect(x: 0, y: 0, width: Float(pixelWidth), height: Float(pixelHeight)), radius: 0, UiColor(0, 0, 0, 110))

        let rowHeight = Self.helpRow * scale, pad = Self.helpPad * scale
        let rules = rulesLines()
        let card = helpCard(lines: rules.count)
        let accent = accentColor
        p.shadow(card, blur: 26 * scale, UiColor(0, 0, 0, 140))
        p.fill(card, radius: 20 * scale, UiColor(18, 20, 28, 175))
        p.outline(card, radius: 20 * scale, UiColor(255, 255, 255, 30))
        p.text(.heading, x: card.x + pad, y: card.y + pad - 4 * scale, tr(.controls), UiPalette.text)
        let top = card.y + pad + 44 * scale
        let leftWidth = (card.width - 2 * pad) * 0.56
        for (index, line) in helpLines.enumerated() {
            let left = index < Self.helpRows
            let columnX = card.x + pad + (left ? 0 : leftWidth)
            let y = top + Float(left ? index : index - Self.helpRows) * rowHeight
            let keysWidth = (left ? 165 : 125) * scale
            p.text(.body, x: columnX, y: y, line.keys, accent)
            p.text(.body, x: columnX + keysWidth, y: y, tr(line.action), UiPalette.text)
        }
        // The rules, in a few sentences.
        var y = top + Float(Self.helpRows) * rowHeight + 12 * scale
        p.text(.body, x: card.x + pad, y: y, tr(.rules), accent)
        for line in rules {
            y += rowHeight
            p.text(.body, x: card.x + pad, y: y, line, UiPalette.muted)
        }
        if button(Widget.helpClose, UiRect(x: card.right - pad - 30 * scale, y: card.y + pad - 8 * scale, width: 30 * scale, height: 30 * scale), "×") ||
            (pointer.leftPressed && !card.contains(pointer.x, pointer.y)) {
            helpVisible = false
        }
        if pointer.leftPressed || pointer.rightPressed {
            pointer.consumed = true
        }
    }

    /// The latest messages, at the bottom, each fading after a few seconds.
    func drawToasts() {
        let p = painter
        let free = freeArea
        var y = Float(pixelHeight) - 40 * scale
        for toast in toasts.reversed() {
            let fade = min(1, toast.age * 6, (2.8 - toast.age) * 3)
            let width = p.measure(.body, toast.text) + 40 * scale, height = 36 * scale
            let pill = UiRect(x: free.x + (free.width - width) / 2, y: y - height, width: width, height: height)
            p.shadow(pill, blur: 14 * scale, UiColor(0, 0, 0, 110).faded(fade))
            p.fill(pill, radius: height / 2, UiColor(20, 22, 30, 225).faded(fade))
            p.textCentered(.body, pill, toast.text, UiPalette.text.faded(fade))
            y -= height + 8 * scale
        }
    }

    func showToast(_ text: String) {
        if toasts.count >= 3 {
            toasts.removeFirst()
        }
        toasts.append(Toast(text: text))
    }

    // MARK: Texts

    func playerName(_ side: StoneColor) -> String {
        if mode == .twoPlayers {
            return tr(.player)
        }
        if isHuman(side) {
            return tr(.you)
        }
        return "\(tr(.computer)) · \(tr(Str.level(level)))"
    }

    func handicapText(_ stones: Int) -> String {
        if stones < 2 {
            return tr(.noHandicap)
        }
        return format(tr(stones <= 4 ? .stonesFew : .stonesMany), "\(stones)")
    }

    /// The winner, once the game is over.
    var resultTitle: String {
        guard let winner = game.winner else { return tr(.draw) }
        return tr(winner == .black ? .blackWins : .whiteWins)
    }

    /// How the game was won: by resignation, or the count.
    var resultDetail: String {
        guard let last = game.moves.last else { return "" }
        if last.isResignation {
            return tr(last.color == .black ? .blackResigned : .whiteResigned)
        }
        let score = game.count()
        return format(tr(.scoreDetail), "\(score.black)", "\(score.white)", Go.format(score.komi)) + "  ·  " + game.resultText
    }
}
