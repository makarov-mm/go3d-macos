import Foundation

/// The colors of the interface.
enum UiPalette {
    static let text = UiColor(236, 239, 245)
    static let muted = UiColor(150, 158, 176)
    static let blackStone = UiColor(22, 22, 26)
    static let whiteStone = UiColor(238, 236, 230)
    static let stoneRim = UiColor(120, 125, 140)
}

/// The interface's widgets; a selector takes two, for its arrows.
enum Widget {
    static let help = 1
    static let pass = 2
    static let resign = 3
    static let estimate = 4
    static let accept = 5
    static let resume = 6
    static let undo = 7
    static let redo = 8
    static let hint = 9
    static let newGame = 10
    static let flip = 11
    static let modeSelector = 12
    static let levelSelector = 14
    static let boardSelector = 16
    static let handicapSelector = 18
    static let themeSelector = 20
    static let sound = 22
    static let coordinates = 23
    static let language = 24
    static let about = 25
    /// Above this, the widgets of the help, the only ones that work while it is open.
    static let modal = 100
    static let helpClose = 101
}

// The panel at the right: the state of the game, the score, the moves, the buttons and the settings.
extension GameController {
    var panelRect: UiRect {
        let width = Self.panelWidth * scale, margin = Self.panelMargin * scale
        return UiRect(x: Float(pixelWidth) - (width + margin) * panelSlide, y: margin, width: width, height: Float(pixelHeight) - 2 * margin)
    }

    /// The window left of the panel.
    var freeArea: UiRect {
        UiRect(x: 0, y: 0, width: min(panelRect.x, Float(pixelWidth)), height: Float(pixelHeight))
    }

    /// The rectangles behind which the scene is frosted.
    func frostedPanels() -> [FrostedPanel] {
        var panels: [FrostedPanel] = []
        func add(_ rect: UiRect, _ radius: Float, _ opacity: Float) {
            panels.append(FrostedPanel(x: rect.x, y: rect.y, width: rect.width, height: rect.height, radius: radius * scale, opacity: opacity))
        }
        if panelSlide > 0.001 {
            add(panelRect, 18, 1)
        }
        if bannerFade > 0.001 {
            add(bannerCard, 18, bannerFade)
        }
        if helpVisible {
            add(helpCard(lines: rulesLines().count), 20, 1)
        }
        return panels
    }

    var accentColor: UiColor { UiColor(linear: Themes.at(theme).accent) }

    func drawInterface() {
        drawPanel()
        drawBanner()
        drawToasts()
        if helpVisible {
            drawHelp()
        }
    }

    // MARK: Widgets

    /// A button that acts when it is released over; an accent one is tinted with the theme's color, as a switch
    /// that is on.
    func button(_ id: Int, _ rect: UiRect, _ label: String, enabled: Bool = true, accent: Bool = false) -> Bool {
        let interactive = enabled && (!helpVisible || id > Widget.modal)
        let hover = interactive && rect.contains(pointer.x, pointer.y)
        if hover {
            wantsHandCursor = true
        }
        if hover && pointer.leftPressed {
            activeWidget = id
            pointer.consumed = true
        }
        var clicked = false
        if pointer.leftReleased && activeWidget == id {
            clicked = hover
            activeWidget = 0
            pointer.consumed = true
        }
        let pressed = hover && activeWidget == id && pointer.leftDown
        var fill = !enabled ? UiColor(255, 255, 255, 7) : pressed ? UiColor(255, 255, 255, 52) : hover ? UiColor(255, 255, 255, 34) : UiColor(255, 255, 255, 17)
        if accent && enabled {
            fill = fill.mixed(with: UiColor(linear: Themes.at(theme).accent, alpha: Float(fill.a) / 255 * 2.2), 0.6)
        }
        painter.fill(rect, radius: 9 * scale, fill)
        painter.textCentered(.body, rect, label, enabled ? UiPalette.text : UiPalette.text.faded(0.35))
        if clicked {
            sound.play(.click)
        }
        return clicked
    }

    /// A label with a value stepped by two arrows; -1 or 1 when one is clicked, else 0.
    func selector(_ id: Int, _ rect: UiRect, _ label: String, _ value: String) -> Int {
        painter.text(.body, x: rect.x, y: rect.y + (rect.height - painter.lineHeight(.body)) / 2, label, UiPalette.muted)
        let arrow = rect.height
        let right = UiRect(x: rect.right - arrow, y: rect.y, width: arrow, height: rect.height)
        let valueRect = UiRect(x: rect.x + rect.width * 0.42, y: rect.y, width: rect.width * 0.58 - arrow - 4 * scale, height: rect.height)
        let left = UiRect(x: valueRect.x - arrow - 4 * scale, y: rect.y, width: arrow, height: rect.height)
        painter.fill(UiRect(x: left.right + 2 * scale, y: rect.y, width: right.x - left.right - 4 * scale, height: rect.height), radius: 9 * scale,
                     UiColor(255, 255, 255, 9))
        painter.textCentered(.body, UiRect(x: left.right, y: rect.y, width: right.x - left.right, height: rect.height), value, UiPalette.text)
        var change = 0
        if button(id, left, "") {
            change = -1
        }
        if button(id + 1, right, "") {
            change = 1
        }
        let size = 5 * scale
        painter.arrow(x: left.x + left.width / 2, y: left.y + left.height / 2, halfWidth: size * 0.8, halfHeight: size, direction: -1, UiPalette.text)
        painter.arrow(x: right.x + right.width / 2, y: right.y + right.height / 2, halfWidth: size * 0.8, halfHeight: size, direction: 1, UiPalette.text)
        return change
    }

    /// A little stone, with a rim and a gleam.
    func drawStone(x: Float, y: Float, radius: Float, _ side: StoneColor) {
        painter.disc(x: x, y: y, radius: radius, UiPalette.stoneRim)
        painter.disc(x: x, y: y, radius: radius - max(1, radius * 0.1), side == .black ? UiPalette.blackStone : UiPalette.whiteStone)
        painter.disc(x: x - radius * 0.28, y: y - radius * 0.3, radius: radius * 0.38, UiColor(255, 255, 255, side == .black ? 46 : 120))
    }

    // MARK: The panel

    func drawPanel() {
        guard panelSlide > 0.001 else { return }
        let p = painter
        let panel = panelRect
        if panel.contains(pointer.x, pointer.y) && (pointer.leftPressed || pointer.rightPressed) {
            pointer.consumed = true
        }
        p.shadow(panel, blur: 22 * scale, UiColor(0, 0, 0, 70))
        p.fill(panel, radius: 18 * scale, UiColor(16, 18, 26, 120))
        p.outline(panel, radius: 18 * scale, UiColor(255, 255, 255, 24))

        // In a low window everything is packed closer, and the footer goes.
        let compact = panel.height < 760 * scale
        let pad = (compact ? 16 : 20) * scale
        let x = panel.x + pad, width = panel.width - 2 * pad
        var y = panel.y + pad

        // The title, with the help and the About window at the right.
        p.text(.heading, x: x, y: y, tr(.title), UiPalette.text)
        let corner = 30 * scale
        if button(Widget.help, UiRect(x: panel.right - pad - corner, y: y - 2 * scale, width: corner, height: corner), "?") {
            helpVisible.toggle()
        }
        if button(Widget.about, UiRect(x: panel.right - pad - 2 * corner - 8 * scale, y: y - 2 * scale, width: corner, height: corner), "i") {
            host?.showAbout()
        }
        y += (compact ? 38 : 44) * scale

        let statusHeight = (compact ? 54 : 62) * scale
        drawStatus(UiRect(x: x, y: y, width: width, height: statusHeight))
        y += statusHeight + (compact ? 8 : 14) * scale
        let scoreHeight = 2 * p.lineHeight(.body) + 66 * scale
        drawScore(UiRect(x: x, y: y, width: width, height: scoreHeight))
        y += scoreHeight + (compact ? 4 : 10) * scale

        // From the bottom up: the footer, the switches, the settings and the buttons; the moves take the space between.
        var bottom = panel.bottom - pad
        if !compact {
            let footerHeight = p.lineHeight(.body)
            p.textCentered(.body, UiRect(x: x, y: bottom - footerHeight, width: width, height: footerHeight), tr(.footer), UiPalette.muted.faded(0.8))
            bottom -= footerHeight + 14 * scale
        }

        let rowHeight = (compact ? 29 : 34) * scale, gap = (compact ? 5 : 8) * scale
        let half = (width - gap) / 2, third = (width - 2 * gap) / 3
        bottom -= rowHeight
        if button(Widget.sound, UiRect(x: x, y: bottom, width: third, height: rowHeight), tr(.sound), accent: sound.enabled) {
            toggleSound()
        }
        if button(Widget.coordinates, UiRect(x: x + third + gap, y: bottom, width: third, height: rowHeight), tr(.coordinates), accent: coordinates) {
            toggleCoordinates()
        }
        if button(Widget.language, UiRect(x: x + 2 * (third + gap), y: bottom, width: third, height: rowHeight), tr(.languageName)) {
            toggleLanguage()
        }
        bottom -= gap

        let modes = [tr(.modeBlack), tr(.modeWhite), tr(.modeTwoPlayers), tr(.modeDemo)]
        let choices: [(id: Int, label: Str, value: String)] = [
            (Widget.themeSelector, .theme, Themes.at(theme).name(language)),
            (Widget.handicapSelector, .handicap, handicapText(handicap)),
            (Widget.boardSelector, .board, "\(boardSize) × \(boardSize)"),
            (Widget.levelSelector, .level, "\(level) · \(tr(Str.level(level)))"),
            (Widget.modeSelector, .mode, modes[mode.rawValue]),
        ]
        for choice in choices {
            bottom -= rowHeight
            let change = selector(choice.id, UiRect(x: x, y: bottom, width: width, height: rowHeight), tr(choice.label), choice.value)
            if change != 0 {
                switch choice.id {
                case Widget.themeSelector:
                    setTheme(theme + change)
                case Widget.handicapSelector:
                    let next = handicap + change
                    setHandicap(next == 1 ? (change > 0 ? 2 : 0) : next)
                case Widget.boardSelector:
                    stepBoardSize(change, wrap: false)
                case Widget.levelSelector:
                    setLevel(level + change)
                default:
                    setMode(mode.rawValue + change)
                }
            }
            bottom -= (compact ? 3 : 6) * scale
        }
        bottom -= (compact ? 4 : 8) * scale

        let buttonHeight = (compact ? 31 : 38) * scale
        bottom -= buttonHeight
        if button(Widget.newGame, UiRect(x: x, y: bottom, width: half, height: buttonHeight), tr(.newGame)) {
            newGame()
        }
        if button(Widget.flip, UiRect(x: x + half + gap, y: bottom, width: half, height: buttonHeight), tr(.flip)) {
            camera.flip()
        }
        bottom -= gap + buttonHeight
        if button(Widget.undo, UiRect(x: x, y: bottom, width: third, height: buttonHeight), tr(.undo), enabled: game.canUndo) {
            undo()
        }
        if button(Widget.redo, UiRect(x: x + third + gap, y: bottom, width: third, height: buttonHeight), tr(.redo), enabled: game.canRedo) {
            redo()
        }
        if button(Widget.hint, UiRect(x: x + 2 * (third + gap), y: bottom, width: third, height: buttonHeight), tr(.hint),
                  enabled: humanToMove && !hintThinking, accent: true) {
            requestHint()
        }
        bottom -= gap + buttonHeight
        if phase == .scoring {
            // The count: accepted as marked, or the game played on.
            if button(Widget.accept, UiRect(x: x, y: bottom, width: half, height: buttonHeight), tr(.accept), enabled: mode != .demo && !findingDead,
                      accent: true) {
                accept()
            }
            if button(Widget.resume, UiRect(x: x + half + gap, y: bottom, width: half, height: buttonHeight), tr(.resume), enabled: mode != .demo) {
                undo()
            }
        } else {
            if button(Widget.pass, UiRect(x: x, y: bottom, width: third, height: buttonHeight), tr(.pass), enabled: humanToMove) {
                playMove(Go.pass)
            }
            // Resigning takes a second click.
            if button(Widget.resign, UiRect(x: x + third + gap, y: bottom, width: third, height: buttonHeight),
                      tr(resignConfirm > 0 ? .confirmResign : .resign), enabled: canResign, accent: resignConfirm > 0) {
                if resignConfirm > 0 {
                    resignByPlayer()
                } else {
                    resignConfirm = 3
                }
            }
            if button(Widget.estimate, UiRect(x: x + 2 * (third + gap), y: bottom, width: third, height: buttonHeight), tr(.estimate),
                      enabled: phase == .playing && !estimating, accent: estimate != nil) {
                requestEstimate()
            }
        }
        bottom -= (compact ? 10 : 16) * scale

        // The moves, where there is room for them.
        let labelHeight = p.lineHeight(.body) + 6 * scale
        if bottom - y - labelHeight > 40 * scale {
            p.text(.body, x: x, y: y, tr(.moves), UiPalette.muted)
            drawMoveList(UiRect(x: x, y: y + labelHeight, width: width, height: bottom - y - labelHeight))
        }
    }

    /// The side to move, or the winner, and what is going on.
    func drawStatus(_ area: UiRect) {
        let p = painter
        let side = game.current.toPlay
        let accent = accentColor
        p.fill(area, radius: 12 * scale, UiColor(255, 255, 255, 14))

        // A stone of the side to move, or of the winner.
        let winner = phase == .finished ? game.winner : nil
        drawStone(x: area.x + 22 * scale, y: area.y + area.height / 2, radius: 10 * scale, winner ?? side)

        let title: String, detail: String
        var titleColor = UiPalette.text
        switch phase {
        case .finished:
            title = resultTitle
            detail = game.moves.last?.isResignation ?? false ? resultDetail : game.resultText
            titleColor = accent
        case .scoring:
            title = tr(.counting)
            detail = tr(findingDead ? .estimating : .countingHelp)
        case .playing:
            title = tr(side == .black ? .blackToMove : .whiteToMove)
            detail = computerThinking || computerResult != nil ? tr(.thinking) : playerName(side)
        }
        let textX = area.x + 44 * scale
        let lineHeight = p.lineHeight(.heading)
        p.text(.heading, x: textX, y: area.y + area.height / 2 - lineHeight + 3 * scale, title, titleColor)
        p.text(.body, x: textX, y: area.y + area.height / 2 + 2 * scale, detail, UiPalette.muted)
        if computerThinking || computerResult != nil || hintThinking || estimating || findingDead {
            p.spinner(x: area.right - 22 * scale, y: area.y + area.height / 2, radius: 8 * scale, thickness: 2.2 * scale, angle: time * 5, accent)
        }
    }

    /// The players with their prisoners while the game goes on; their points when it is counted.
    func drawScore(_ area: UiRect) {
        let p = painter
        let counted = isCounted
        let score = counted ? game.count() : Score(komi: game.komi)
        let rowHeight = 28 * scale
        // What the numbers are, over them.
        let caption = tr(counted ? .points : .captures)
        p.text(.body, x: area.right - p.measure(.body, caption), y: area.y, caption, UiPalette.muted.faded(0.8))
        var y = area.y + p.lineHeight(.body) + 2 * scale
        for side in [StoneColor.black, .white] {
            let textY = y + (rowHeight - p.lineHeight(.body)) / 2
            let toMove = phase == .playing && game.current.toPlay == side
            drawStone(x: area.x + 9 * scale, y: y + rowHeight / 2, radius: 7 * scale, side)
            let who: Str = mode == .twoPlayers ? .player : isHuman(side) ? .you : .computer
            p.text(.body, x: area.x + 26 * scale, y: textY, "\(tr(side == .black ? .black : .white))  ·  \(tr(who))",
                   toMove ? UiPalette.text : UiPalette.text.faded(0.75))
            let value: String
            if counted {
                value = side == .black ? "\(score.black)" : "\(score.white) + \(Go.format(score.komi))"
            } else {
                value = "\(game.current.captures(by: side))"
            }
            p.text(.heading, x: area.right - p.measure(.heading, value), y: y + (rowHeight - p.lineHeight(.heading)) / 2, value, UiPalette.text)
            y += rowHeight
        }
        y += 8 * scale
        if counted {
            // A bar shared out between the colors, komi with White.
            let bar = UiRect(x: area.x, y: y, width: area.width, height: 6 * scale)
            let total = max(1, Double(score.black + score.white) + score.komi)
            let share = Float(Double(score.black) / total)
            p.fill(bar, radius: 3 * scale, UiColor(238, 236, 230, 220))
            p.fill(UiRect(x: bar.x, y: bar.y, width: max(bar.height, bar.width * share), height: bar.height), radius: 3 * scale, UiColor(10, 10, 12, 235))
            p.fill(UiRect(x: bar.x + bar.width / 2 - 0.5 * scale, y: bar.y - 2 * scale, width: 1 * scale, height: bar.height + 4 * scale), radius: 0,
                   UiColor(255, 255, 255, 90))
        } else {
            var line = "\(game.size) × \(game.size)  ·  \(tr(.komi)) \(Go.format(game.komi))"
            if game.handicap >= 2 {
                line += "  ·  \(tr(.handicap)): \(game.handicap)"
            }
            p.text(.body, x: area.x, y: y - 4 * scale, line, UiPalette.muted)
        }
    }

    /// The moves, two to a row, scrolled by the wheel and following the game.
    func drawMoveList(_ area: UiRect) {
        let p = painter
        p.fill(area, radius: 12 * scale, UiColor(0, 0, 0, 40))
        let moves = game.moves
        if moves.isEmpty {
            p.textCentered(.body, area, tr(.noMovesYet), UiPalette.muted)
            return
        }

        let rowHeight = (25 * scale).rounded()
        let inner = area.inset(8 * scale)
        let visible = max(1, Int(inner.height / rowHeight))
        // Each row starts with Black's move; with a handicap White begins, in the second column.
        let offset = game.start.toPlay == .white ? 1 : 0
        let rows = (moves.count + offset + 1) / 2
        let maxScroll = Float(max(0, rows - visible))

        if area.contains(pointer.x, pointer.y) && pointer.wheel != 0 && !helpVisible {
            moveScroll = clamp(moveScroll - pointer.wheel * 3, 0, maxScroll)
            followMoves = moveScroll >= maxScroll
            pointer.wheel = 0
        }
        if followMoves {
            moveScroll = maxScroll
        }
        moveScroll = clamp(moveScroll, 0, maxScroll)

        let first = Int(moveScroll)
        let numberWidth = 40 * scale, columnWidth = (inner.width - numberWidth) / 2
        let accent = accentColor
        for row in stride(from: first, to: min(rows, first + visible), by: 1) {
            let y = inner.y + Float(row - first) * rowHeight
            let number = "\(row + 1)."
            p.text(.body, x: inner.x + numberWidth - 10 * scale - p.measure(.body, number), y: y + 3 * scale, number, UiPalette.muted)
            for column in 0..<2 {
                let ply = row * 2 + column - offset
                guard ply >= 0 && ply < moves.count else { continue }
                let x = inner.x + numberWidth + Float(column) * columnWidth
                if ply == moves.count - 1 {
                    p.fill(UiRect(x: x - 6 * scale, y: y + 1 * scale, width: columnWidth - 6 * scale, height: rowHeight - 2 * scale), radius: 7 * scale,
                           accent.faded(0.28))
                }
                let record = moves[ply]
                if record.isPass {
                    p.text(.body, x: x, y: y + 3 * scale, tr(.pass), UiPalette.muted)
                } else if record.isResignation {
                    p.text(.body, x: x, y: y + 3 * scale, tr(.resign), UiPalette.muted)
                } else {
                    // The point, and the stones it took.
                    let width = p.text(.body, x: x, y: y + 3 * scale, Go.name(record.point, size: game.size), UiPalette.text)
                    if !record.captured.isEmpty {
                        p.text(.body, x: x + width + 8 * scale, y: y + 3 * scale, "×\(record.captured.count)", UiPalette.muted.faded(0.85))
                    }
                }
            }
        }
        if maxScroll > 0 {
            // A thin scroll bar.
            let barHeight = inner.height * Float(visible) / Float(rows)
            let barY = inner.y + (inner.height - barHeight) * (moveScroll / maxScroll)
            p.fill(UiRect(x: area.right - 5 * scale, y: barY, width: 3 * scale, height: barHeight), radius: 1.5 * scale, UiColor(255, 255, 255, 50))
        }
    }
}
