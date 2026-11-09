import AppKit
import Metal
import QuartzCore

/// What the game asks of the application around it.
@MainActor
protocol GameHost: AnyObject {
    var isFullScreen: Bool { get }
    func toggleFullScreen()
    func showAbout()
    /// The interface's language changed: the menus and the window's title follow it.
    func languageChanged()
}

/// Runs the game, the computer players and the interface, and draws them, a frame at a time as the view asks; the
/// view stops asking while nothing moves.
@MainActor
final class GameController {
    enum Mode: Int {
        case playBlack, playWhite, twoPlayers, demo
    }

    /// What the mouse did since the last frame, in pixels from the top left.
    struct Pointer {
        var x: Float = -1, y: Float = -1
        var leftDown = false, rightDown = false
        var leftPressed = false, leftReleased = false, rightPressed = false, rightReleased = false
        var wheel: Float = 0
        var consumed = false // taken by the interface
    }

    enum Gesture {
        case none, pressPoint, turnCamera
    }

    struct Toast {
        var text: String
        var age: Float = 0
    }

    static let panelWidth: Float = 344
    static let panelMargin: Float = 16
    static let boardSizes = [9, 13, 19]

    weak var host: (any GameHost)?
    let view: GameView
    let renderer: Renderer
    let painter: UiPainter
    let sound = SoundBank()
    var settings: Settings
    var language: Language

    /// The drawable's size, in pixels.
    var pixelWidth = 0, pixelHeight = 0
    /// Pixels to a point.
    var scale: Float = 1
    private var fontScale: Float = 0
    private var lastFrame = CACurrentMediaTime()
    var time: Float = 0
    /// Something to draw since the last frame.
    var dirty = true
    /// Frames the GPU may still be working on, so that their buffers are not written again too soon.
    private let inFlight = DispatchSemaphore(value: BufferRing.count)

    var game: Game
    var layout: BoardLayout
    var camera = OrbitCamera()
    var boardView = BoardView()
    var mode = Mode.playBlack
    var level = 2
    var theme = 0
    var boardSize = 9 // for new games
    var handicap = 0  // for new games
    var coordinates = true

    let computer = Worker<SearchResult>()
    var computerThinking = false
    var computerClock: Float = 0
    var computerResult: SearchResult?
    let hinter = Worker<SearchResult>()
    var hintThinking = false
    var hint: GoPoint?
    var hintGlow: Float = 0
    let estimator = Worker<Ownership>()
    var estimating = false
    var estimate: Ownership? // shown over the board until the position changes
    let deadFinder = Worker<Ownership>() // at the start of the counting
    var findingDead = false
    var deadFoundPly = -1
    var scoringClock: Float = 0
    var resignConfirm: Float = 0 // while above zero, a second click on Resign resigns
    var announcedEnd = false
    var events: [BoardView.Event] = []

    var pointer = Pointer()
    var gesture = Gesture.none
    var pressX: Float = 0, pressY: Float = 0
    var dragX: Float = 0, dragY: Float = 0 // the pointer when the camera last turned
    var pressPoint = Go.pass
    var hoverPoint = Go.pass // a legal point under the pointer, or a stone while counting
    var wantsHandCursor = false

    var activeWidget = 0
    var panelVisible = true
    var panelSlide: Float = 1
    var helpVisible = false
    var moveScroll: Float = 0
    var followMoves = true
    var bannerFade: Float = 0
    var bannerTitle = "", bannerDetail = "" // kept while the banner fades after a new game
    var toasts: [Toast] = []

    init(view: GameView, device: any MTLDevice) throws {
        let saved = Settings.load()
        self.view = view
        settings = saved
        language = saved.language
        theme = saved.theme
        level = saved.level
        mode = Mode(rawValue: saved.mode) ?? .playBlack
        boardSize = saved.boardSize
        handicap = saved.handicap
        coordinates = saved.coordinates
        panelVisible = saved.panel
        panelSlide = saved.panel ? 1 : 0

        let shaders = try ShaderLibrary(device: device)
        renderer = try Renderer(shaders: shaders, stoneShape: StoneModel.build())
        painter = try UiPainter(shaders: shaders)

        let loaded = (try? Game.fromSgf(saved.game)) ?? Game(size: saved.boardSize, handicap: saved.handicap)
        game = loaded
        layout = BoardLayout(size: loaded.size)

        sound.enabled = saved.sound
        renderer.setTheme(Themes.at(theme))
        renderer.setLayout(layout)
        boardView.setLayout(layout)
        boardView.rebuild(game, animate: true)
        camera.setReach(layout.extent)
        camera.reset(viewSide)
        announcedEnd = phase == .finished
    }

    // MARK: The frame

    /// Draws a frame. The view stops asking for frames when nothing moves, so that a game left alone takes no time.
    func drawFrame() {
        // Nothing is drawn, and the game waits, while the window cannot be seen.
        guard let window = view.window, window.occlusionState.contains(.visible) else {
            view.isPaused = true
            return
        }
        dirty = false
        let now = CACurrentMediaTime()
        let seconds = Float(min(now - lastFrame, 0.1))
        lastFrame = now
        time += seconds
        let size = view.drawableSize
        pixelWidth = Int(size.width)
        pixelHeight = Int(size.height)
        scale = Float(window.backingScaleFactor)
        guard pixelWidth > 0 && pixelHeight > 0 else { return }
        if scale != fontScale {
            buildFonts()
        }
        guard fontScale == scale, (try? renderer.resize(width: pixelWidth, height: pixelHeight)) != nil else { return }

        update(seconds)
        let scene = buildScene()
        inFlight.wait()
        guard let commandBuffer = renderer.queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let inFlight = inFlight
        commandBuffer.addCompletedHandler { @Sendable _ in inFlight.signal() }
        renderer.encodeScene(scene, into: commandBuffer)

        wantsHandCursor = false
        painter.begin(width: pixelWidth, height: pixelHeight)
        drawInterface()
        if let drawable = view.currentDrawable {
            renderer.encodeComposite(scene, into: commandBuffer, target: drawable.texture) { painter.flush(into: $0) }
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        handleBoardPointer()

        pointer.leftPressed = false
        pointer.leftReleased = false
        pointer.rightPressed = false
        pointer.rightReleased = false
        pointer.wheel = 0
        pointer.consumed = false
        view.showHandCursor(wantsHandCursor)
        view.isPaused = !(dirty || needsAnimation)
    }

    /// Something happened that the next frame should show.
    func requestFrame() {
        dirty = true
        if view.isPaused {
            lastFrame = CACurrentMediaTime() // the time spent waiting is not animation time
            view.isPaused = false
        }
    }

    private func buildFonts() {
        do {
            let device = renderer.device
            let body = try FontAtlas(device: device, pixelSize: CGFloat(15 * scale), weight: .regular)
            let heading = try FontAtlas(device: device, pixelSize: CGFloat(19 * scale), weight: .semibold)
            let display = try FontAtlas(device: device, pixelSize: CGFloat(31 * scale), weight: .semibold)
            painter.setFonts(body, heading, display)
            fontScale = scale
        } catch {
            fontScale = 0
        }
    }

    private func update(_ seconds: Float) {
        let target: Float = panelVisible ? 1 : 0
        panelSlide += (target - panelSlide) * (1 - exp(-seconds * 12))
        if abs(target - panelSlide) < 0.001 {
            panelSlide = target
        }
        let panelSpace = (Self.panelWidth + Self.panelMargin) * scale * panelSlide
        camera.setSpace(1 - panelSpace / Float(max(pixelWidth, 1)))
        camera.update(seconds)

        // The stones that the move under the pointer would take glow and rise, about to go.
        var taking: [GoPoint] = []
        if hoverPoint != Go.pass && humanToMove && boardView.isBoardReady {
            var next = game.current
            taking = next.play(hoverPoint, next.toPlay, recordCaptures: true)
        }
        boardView.preview(taking)

        // One sound of each kind a frame: the stones taken land together.
        events.removeAll(keepingCapacity: true)
        boardView.update(seconds, events: &events)
        for event in Set(events).sorted() {
            switch event {
            case .place: sound.play(.place)
            case .capture: sound.play(.capture)
            case .returnToBowl: sound.play(.returnToBowl)
            }
        }

        let over = phase == .finished && boardView.isSettled
        if over {
            bannerTitle = resultTitle
            bannerDetail = resultDetail
        }
        bannerFade = clamp(bannerFade + (over ? seconds : -seconds) * 3, 0, 1)
        hintGlow = clamp(hintGlow + (hint != nil ? seconds : -seconds) * 4, 0, 1)
        resignConfirm = max(0, resignConfirm - seconds)
        for index in toasts.indices {
            toasts[index].age += seconds
        }
        toasts.removeAll { $0.age > 3.2 }

        updateHelpers()
        updateComputer(seconds)
        updateScoring(seconds)

        if over && !announcedEnd {
            announcedEnd = true
            sound.play(.gameOver)
        }
        if phase != .finished {
            announcedEnd = false
        }
    }

    private var needsAnimation: Bool {
        camera.isMoving || boardView.isAnimating || computerThinking || computerResult != nil || hintThinking || estimating || findingDead ||
            !toasts.isEmpty || (panelSlide > 0 && panelSlide < 1) || (bannerFade > 0 && bannerFade < 1) || hintGlow > 0 ||
            resignConfirm > 0 || gesture != .none || pointer.leftDown || pointer.rightDown ||
            (phase == .playing && !isHuman(game.current.toPlay)) || (phase == .scoring && mode == .demo)
    }

    private func buildScene() -> RenderScene {
        let theme = Themes.at(self.theme)
        let board = game.current
        let size = board.size

        var scene = RenderScene()
        scene.view = camera.view
        scene.projection = camera.projection(aspect: Float(pixelWidth) / Float(pixelHeight))
        scene.eye = camera.eye
        scene.time = time
        scene.coordinates = coordinates
        func markIndex(_ point: GoPoint) -> Int { Go.x(point) + Go.maxSize * Go.y(point) }

        // The stone played last carries a ring; after a pass there is none.
        var lastMove = Go.pass
        if let last = game.moves.last, last.point > Go.pass {
            lastMove = last.point
        }

        // The territory, as counted at the end or estimated on request; the stones that are dead in it are seen through.
        var seeThrough = [Bool](repeating: false, count: Go.pointCount)
        var marked = false
        if isCounted {
            let owner = game.territory()
            let dead = game.dead
            for y in 0..<size {
                for x in 0..<size {
                    let point = Go.point(x, y)
                    if board.isStone(point) && !dead[point] {
                        continue
                    }
                    if owner[point] == .black {
                        scene.marks[markIndex(point)] |= SceneMark.blackArea
                    } else if owner[point] == .white {
                        scene.marks[markIndex(point)] |= SceneMark.whiteArea
                    }
                }
            }
            seeThrough = dead
            marked = true
        } else if let estimate {
            scene.estimate = true
            for y in 0..<size {
                for x in 0..<size {
                    let point = Go.point(x, y)
                    let share = estimate.black[point]
                    let cell = board.cell(at: point)
                    if share > 0.7 && cell != .black {
                        scene.marks[markIndex(point)] |= SceneMark.blackArea
                        seeThrough[point] = cell == .white
                    } else if share < 0.3 && cell != .white {
                        scene.marks[markIndex(point)] |= SceneMark.whiteArea
                        seeThrough[point] = cell == .black
                    }
                }
            }
            marked = true
        }
        scene.stones = boardView.draws(lastMove: lastMove, dead: marked ? seeThrough : nil, warning: theme.accentWarm, time: time)
        boardView.markStones(&scene.marks)

        // The stone that a click would place, seen through; while counting, the group under the pointer.
        let ready = humanToMove && boardView.isBoardReady
        if ready && hoverPoint != Go.pass {
            var ghost = StoneDraw()
            ghost.model = Mat4.translation(layout.center(of: hoverPoint) + Vec3(0, StoneModel.halfHeight + 0.015, 0)) * Mat4.rotationY(0.7)
            ghost.white = board.toPlay == .white
            ghost.seed = 0.37
            ghost.opacity = 0.5
            scene.stones.append(ghost)
        }
        if phase == .scoring && hoverPoint != Go.pass {
            scene.marks[markIndex(hoverPoint)] |= SceneMark.hover
        }
        if let hint, hintGlow > 0.01 {
            scene.marks[markIndex(hint)] |= SceneMark.hint
        }
        if ready && board.ko != Go.pass {
            scene.marks[markIndex(board.ko)] |= SceneMark.ko
        }
        scene.panels = frostedPanels()
        return scene
    }

    // MARK: State

    var phase: GamePhase { game.phase }

    /// The game was counted, rather than resigned or still going on.
    var isCounted: Bool {
        phase == .scoring || (phase == .finished && !(game.moves.last?.isResignation ?? false))
    }

    func isHuman(_ side: StoneColor) -> Bool {
        switch mode {
        case .playBlack: side == .black
        case .playWhite: side == .white
        case .twoPlayers: true
        case .demo: false
        }
    }

    var humanToMove: Bool { phase == .playing && isHuman(game.current.toPlay) }
    var viewSide: StoneColor { mode == .playWhite ? .white : .black }

    func tr(_ id: Str) -> String { id.text(language) }

    func save() {
        settings.theme = theme
        settings.level = level
        settings.mode = mode.rawValue
        settings.boardSize = boardSize
        settings.handicap = handicap
        settings.coordinates = coordinates
        settings.sound = sound.enabled
        settings.panel = panelVisible
        settings.language = language
        // Without the players' names, and on one line.
        settings.game = game.sgf(blackName: "", whiteName: "").replacingOccurrences(of: "\n", with: " ")
        settings.save()
    }
}
