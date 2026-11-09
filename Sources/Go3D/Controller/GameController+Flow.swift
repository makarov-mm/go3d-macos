import AppKit

// The game: moves, the computer players, the helpers and the choices of the panel and the menus.
extension GameController {
    /// The threads of a search: all the cores but one, for the window, and at most eight.
    static var searchThreads: Int { min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 1), 8) }

    /// The playouts, the time and the threads of each level.
    static func levelLimits(_ level: Int, seed: UInt64) -> SearchLimits {
        let threads = searchThreads
        switch level {
        case 1: return SearchLimits(playouts: 300, milliseconds: 1000, threads: 1, mayResign: true, seed: seed)
        case 2: return SearchLimits(playouts: 1500, milliseconds: 1500, threads: min(threads, 2), mayResign: true, seed: seed)
        case 3: return SearchLimits(playouts: 6000, milliseconds: 2000, threads: threads, mayResign: true, seed: seed)
        case 4: return SearchLimits(playouts: 30000, milliseconds: 2500, threads: threads, mayResign: true, seed: seed)
        default: return SearchLimits(playouts: 200_000, milliseconds: 6000, threads: threads, mayResign: true, seed: seed)
        }
    }

    /// Playouts for an estimate of the score: enough to be steady, and quick on the big board too.
    static func estimatePlayouts(_ size: Int) -> Int { size <= 9 ? 4000 : size <= 13 ? 3000 : 2400 }

    static func nextSeed() -> UInt64 { UInt64.random(in: .min ... .max) }

    // MARK: The computer and the helpers

    func stopWorkers() {
        computer.cancel()
        computerThinking = false
        computerResult = nil
        hinter.cancel()
        hintThinking = false
        estimator.cancel()
        estimating = false
        deadFinder.cancel()
        findingDead = false
    }

    func updateComputer(_ seconds: Float) {
        guard phase == .playing, !isHuman(game.current.toPlay) else { return }
        computerClock += seconds
        if !computerThinking && computerResult == nil {
            let board = game.current
            let history = game.history
            let komi = game.komi
            let limits = Self.levelLimits(level, seed: Self.nextSeed())
            computer.start { stop in Engine.search(board, history: history, komi: komi, limits: limits, stop: stop) }
            computerThinking = true
            computerClock = 0
        }
        if computerThinking {
            let (busy, result) = computer.poll()
            if let result {
                computerResult = result
                computerThinking = false
            } else if !busy {
                computerThinking = false // cancelled; a new search starts next frame
            }
        }
        // The computer waits for the stones to settle, and a moment more, so that its move can be followed.
        let pause: Float = mode == .demo ? 0.6 : 0.25
        if let result = computerResult, boardView.isSettled, computerClock >= pause, gesture == .none {
            computerResult = nil
            if result.resign {
                resign(game.current.toPlay)
            } else {
                playMove(result.move)
            }
        }
    }

    /// After two passes the dead stones are found, to be corrected by a click; a demonstration accepts the count by
    /// itself.
    func updateScoring(_ seconds: Float) {
        guard phase == .scoring else { return }
        if deadFoundPly != game.ply && !findingDead {
            let board = game.current
            let komi = game.komi
            let playouts = Self.estimatePlayouts(board.size)
            let seed = Self.nextSeed()
            deadFinder.start { stop in Engine.estimate(board, komi: komi, playouts: playouts, seed: seed, stop: stop) }
            findingDead = true
        }
        if findingDead {
            let (busy, result) = deadFinder.poll()
            if let result {
                findingDead = false
                game.setDead(result.dead(on: game.current))
                deadFoundPly = game.ply
                scoringClock = 0
            } else if !busy {
                findingDead = false
            }
        }
        if mode == .demo && deadFoundPly == game.ply && !findingDead {
            scoringClock += seconds
            if scoringClock > 1.6 {
                accept()
            }
        }
    }

    func updateHelpers() {
        if hintThinking {
            let (busy, result) = hinter.poll()
            if let result {
                hintThinking = false
                if humanToMove {
                    if result.move == Go.pass {
                        showToast(tr(.hintPass))
                    } else {
                        hint = result.move
                        showToast(tr(.hintToast) + Go.name(result.move, size: game.size))
                    }
                }
            } else if !busy {
                hintThinking = false
            }
        }
        if estimating {
            let (busy, result) = estimator.poll()
            if let result {
                estimating = false
                estimate = result
                let leader = tr(result.margin >= 0 ? .black : .white)
                showToast(format(tr(.estimateToast), leader, String(format: "%.1f", abs(result.margin))))
            } else if !busy {
                estimating = false
            }
        }
    }

    func requestHint() {
        guard humanToMove, !hintThinking else { return }
        hint = nil
        let board = game.current
        let history = game.history
        let komi = game.komi
        let limits = SearchLimits(playouts: 60000, milliseconds: 1500, threads: Self.searchThreads, mayResign: false, seed: Self.nextSeed())
        hinter.start { stop in Engine.search(board, history: history, komi: komi, limits: limits, stop: stop) }
        hintThinking = true
    }

    /// The territory as it stands, shown until the next move; a second request hides it.
    func requestEstimate() {
        guard phase == .playing else { return }
        if estimate != nil {
            estimate = nil
            return
        }
        guard !estimating else { return }
        let board = game.current
        let komi = game.komi
        let playouts = Self.estimatePlayouts(board.size)
        let seed = Self.nextSeed()
        estimator.start { stop in Engine.estimate(board, komi: komi, playouts: playouts, seed: seed, stop: stop) }
        estimating = true
    }

    // MARK: Moves

    func newGame() {
        startGame(Game(size: boardSize, handicap: handicap))
    }

    /// Sets out a game, with the board of its size.
    func startGame(_ newGame: Game) {
        stopWorkers()
        let resize = newGame.size != layout.size
        game = newGame
        if resize {
            layout = BoardLayout(size: game.size)
            renderer.setLayout(layout)
            boardView.setLayout(layout)
            camera.setReach(layout.extent)
        }
        boardView.rebuild(game, animate: true)
        camera.reset(viewSide)
        announcedEnd = phase == .finished
        deadFoundPly = -1
        afterPositionChange()
    }

    func playMove(_ point: GoPoint) {
        guard game.play(point), let record = game.moves.last else { return }
        boardView.playMove(record, forward: true)
        if point == Go.pass {
            announcePass()
        }
        afterPositionChange()
    }

    /// A toast and a bell for a pass, or the start of the counting after two.
    func announcePass() {
        guard let last = game.moves.last, last.isPass else { return }
        if phase == .scoring {
            showToast(tr(.bothPassed))
        } else {
            showToast(tr(last.color == .black ? .blackPasses : .whitePasses))
        }
        sound.play(.pass)
    }

    func resign(_ who: StoneColor) {
        guard phase != .finished else { return }
        stopWorkers()
        game.resign(who)
        afterPositionChange()
    }

    /// The side that resigns from the panel or the menu: the one to move between two players, else the player's.
    func resignByPlayer() {
        guard canResign else { return }
        resign(mode == .twoPlayers ? game.current.toPlay : viewSide)
    }

    var canResign: Bool { phase == .playing && mode != .demo }

    /// Resigning from the menu asks first, as the panel's button does with a second click.
    func confirmResign() {
        guard canResign, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = tr(.resignQuestion)
        alert.addButton(withTitle: tr(.resign))
        alert.addButton(withTitle: tr(.cancel))
        alert.buttons[0].hasDestructiveAction = true
        let ply = game.ply
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn, self.game.ply == ply else { return }
            self.resignByPlayer()
            self.requestFrame()
        }
    }

    func accept() {
        guard phase == .scoring, !findingDead else { return }
        deadFinder.cancel()
        findingDead = false
        game.accept()
        hoverPoint = Go.pass
        save()
    }

    func undo() {
        stopWorkers()
        guard game.canUndo else {
            showToast(tr(.nothingToUndo))
            return
        }
        func undoOne() {
            guard let record = game.moves.last else { return }
            game.undo()
            boardView.playMove(record, forward: false)
        }
        undoOne()
        // Against the computer, back to the player's own turn.
        while (mode == .playBlack || mode == .playWhite) && game.canUndo && !humanToMove {
            undoOne()
        }
        afterPositionChange()
    }

    func redo() {
        stopWorkers()
        guard game.canRedo else { return }
        func redoOne() {
            game.redo()
            if let record = game.moves.last {
                boardView.playMove(record, forward: true)
            }
        }
        redoOne()
        while (mode == .playBlack || mode == .playWhite) && game.canRedo && phase == .playing && !humanToMove {
            redoOne()
        }
        afterPositionChange()
    }

    func afterPositionChange() {
        hinter.cancel()
        hintThinking = false
        hint = nil
        estimator.cancel()
        estimating = false
        estimate = nil
        deadFinder.cancel()
        findingDead = false
        resignConfirm = 0
        hoverPoint = Go.pass
        followMoves = true
        save()
    }

    // MARK: Choices

    func setMode(_ newMode: Int) {
        stopWorkers()
        mode = Mode(rawValue: (newMode % 4 + 4) % 4) ?? .playBlack
        if mode == .playBlack || mode == .playWhite {
            camera.face(viewSide)
        }
        hint = nil
        save()
    }

    func setLevel(_ newLevel: Int) {
        level = clamp(newLevel, 1, 5)
        if computerThinking {
            computer.cancel() // starts again at the new level
            computerThinking = false
        }
        save()
    }

    /// The size and the handicap are for the next game; a game not yet begun or already over is set out again at once.
    func setBoardSize(_ size: Int) {
        boardSize = size
        handicap = min(handicap, Go.maxHandicap(size: size))
        if game.ply == 0 || phase == .finished {
            newGame()
        } else {
            showToast(tr(.nextGame))
        }
        save()
    }

    func setHandicap(_ stones: Int) {
        handicap = clamp(stones, 0, Go.maxHandicap(size: boardSize))
        if handicap == 1 {
            handicap = 0
        }
        if game.ply == 0 || phase == .finished {
            newGame()
        } else {
            showToast(tr(.nextGame))
        }
        save()
    }

    /// The next board size, or the one before.
    func stepBoardSize(_ step: Int, wrap: Bool) {
        let at = Self.boardSizes.firstIndex(of: boardSize) ?? 0
        let count = Self.boardSizes.count
        let next = wrap ? ((at + step) % count + count) % count : clamp(at + step, 0, count - 1)
        setBoardSize(Self.boardSizes[next])
    }

    func setTheme(_ newTheme: Int) {
        let count = Themes.all.count
        theme = (newTheme % count + count) % count
        renderer.setTheme(Themes.at(theme))
        save()
    }

    func toggleCoordinates() {
        coordinates.toggle()
        save()
    }

    func toggleSound() {
        sound.enabled.toggle()
        save()
    }

    func toggleLanguage() {
        language = language.other
        save()
        host?.languageChanged()
    }

    func togglePanel() {
        panelVisible.toggle()
        save()
    }

    // MARK: The clipboard

    func copyGame() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(game.sgf(blackName: playerName(.black), whiteName: playerName(.white)), forType: .string)
        showToast(tr(.gameCopied))
    }

    func pasteGame() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard let loaded = try? Game.fromSgf(text) else {
            showToast(tr(.nothingToPaste))
            return
        }
        boardSize = loaded.size // new games go on with the size of the one loaded
        handicap = min(handicap, Go.maxHandicap(size: boardSize))
        startGame(loaded)
        showToast(tr(.gameLoaded))
    }

    // MARK: The menus

    func perform(_ command: GameCommand) {
        requestFrame()
        switch command {
        case .newGame: newGame()
        case .undo: undo()
        case .redo: redo()
        case .pass:
            if humanToMove {
                playMove(Go.pass)
            }
        case .resign: confirmResign()
        case .hint: requestHint()
        case .estimate: requestEstimate()
        case .accept: accept()
        case .copyGame: copyGame()
        case .pasteGame: pasteGame()
        case .flip: camera.flip()
        case .topView: camera.toggleTopView()
        case .resetView: camera.reset(viewSide)
        case .panel: togglePanel()
        case .nextTheme: setTheme(theme + 1)
        case .help: helpVisible.toggle()
        }
    }

    func canPerform(_ command: GameCommand) -> Bool {
        switch command {
        case .undo: game.canUndo
        case .redo: game.canRedo
        case .pass: humanToMove
        case .resign: canResign
        case .hint: humanToMove && !hintThinking
        case .estimate: phase == .playing && !estimating
        case .accept: phase == .scoring && mode != .demo && !findingDead
        default: true
        }
    }

    /// Whether a menu item shows a check mark.
    func isChecked(_ command: GameCommand) -> Bool {
        switch command {
        case .estimate: estimate != nil
        case .panel: panelVisible
        case .help: helpVisible
        default: false
        }
    }
}
