import Foundation

/// The phase of a game: moves are played, then after two passes the dead stones are marked and the count accepted.
enum GamePhase: Sendable {
    case playing
    case scoring
    case finished
}

struct MoveRecord: Sendable {
    /// A stone, `Go.pass` or `Go.resignation`.
    var point: GoPoint = Go.pass
    var color: StoneColor = .black
    var captured: [GoPoint] = []

    var isPass: Bool { point == Go.pass }
    var isResignation: Bool { point == Go.resignation }
}

/// Area scoring: stones and the territory they surround; komi goes to White.
struct Score: Sendable {
    var black = 0
    var white = 0
    var komi = 0.0

    /// Above zero, Black wins.
    var margin: Double { Double(black - white) - komi }
}

/// A game: the size, the handicap and komi, the moves played and those taken back, and at the end the dead stones
/// the players agree on.
struct Game: Sendable {
    private(set) var handicap = 0
    private(set) var komi = 7.5
    private var positions: [Board] = []
    /// The hashes of the positions so far, for superko.
    private(set) var history: [UInt64] = []
    private(set) var moves: [MoveRecord] = []
    private var redoMoves: [MoveRecord] = [] // the next to replay at the end
    private(set) var dead = [Bool](repeating: false, count: Go.pointCount)
    private var accepted = false

    init(size: Int = 9, handicap: Int = 0) {
        reset(size: size, handicap: handicap)
    }

    /// A new game; komi is 7.5, or 0.5 with a handicap.
    mutating func reset(size: Int, handicap: Int) {
        var start = Board(size: size)
        let stones = handicap >= 2 ? min(handicap, Go.maxHandicap(size: start.size)) : 0
        for point in Go.handicapPoints(size: start.size, stones: stones) {
            start.setup(point, .black)
        }
        if stones > 0 {
            start.setToPlay(.white)
        }
        begin(start, handicap: stones, komi: stones > 0 ? 0.5 : 7.5)
    }

    private mutating func begin(_ start: Board, handicap: Int, komi: Double) {
        self.handicap = handicap
        self.komi = komi
        positions = [start]
        history = [start.hash]
        moves = []
        redoMoves = []
        dead = [Bool](repeating: false, count: Go.pointCount)
        accepted = false
    }

    var size: Int { start.size }
    var current: Board { positions[positions.count - 1] }
    var start: Board { positions[0] }
    var ply: Int { moves.count }
    var canUndo: Bool { !moves.isEmpty }
    var canRedo: Bool { !redoMoves.isEmpty }

    var phase: GamePhase {
        if let last = moves.last, last.isResignation {
            return .finished
        }
        if current.passes >= 2 {
            return accepted ? .finished : .scoring
        }
        return .playing
    }

    // MARK: Moves

    /// Legal with positional superko: no move may bring back an earlier position.
    func isLegal(_ point: GoPoint) -> Bool {
        guard phase == .playing else { return false }
        let board = current
        if point == Go.pass {
            return true
        }
        guard board.isLegal(point, board.toPlay) else { return false }
        var next = board
        next.play(point, board.toPlay)
        return !history.contains(next.hash)
    }

    /// A stone or a pass; after two passes the game goes to scoring.
    @discardableResult
    mutating func play(_ point: GoPoint) -> Bool {
        guard isLegal(point) else { return false }
        push(point, current.toPlay)
        redoMoves.removeAll()
        return true
    }

    mutating func resign(_ who: StoneColor) {
        guard phase != .finished else { return }
        push(Go.resignation, who)
        redoMoves.removeAll()
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let last = moves.popLast() else { return false }
        redoMoves.append(last)
        positions.removeLast()
        history.removeLast()
        clearCount()
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = redoMoves.popLast() else { return false }
        push(next.point, next.color)
        return true
    }

    private mutating func push(_ point: GoPoint, _ color: StoneColor) {
        var record = MoveRecord(point: point, color: color)
        var next = current
        if point != Go.resignation {
            record.captured = next.play(point, color, recordCaptures: true)
        }
        positions.append(next)
        history.append(next.hash)
        moves.append(record)
        clearCount()
    }

    private mutating func clearCount() {
        dead = [Bool](repeating: false, count: Go.pointCount)
        accepted = false
    }

    // MARK: Scoring

    /// The dead stones, as found by the computer.
    mutating func setDead(_ marked: [Bool]) {
        let board = current
        for point in 0..<Go.pointCount {
            dead[point] = marked[point] && board.isStone(point)
        }
    }

    /// Marks a group dead or alive: the stones of the color clicked in the area they share, reached through their
    /// own stones and empty points.
    mutating func toggleDead(_ point: GoPoint) {
        let board = current
        guard board.isStone(point) else { return }
        let color = board.cell(at: point)
        let isDead = !dead[point]
        var seen = [Bool](repeating: false, count: Go.pointCount)
        var stack = [point]
        seen[point] = true
        while let at = stack.popLast() {
            if board.cell(at: at) == color {
                dead[at] = isDead
            }
            for direction in 0..<4 {
                let next = Go.neighbour(at, direction)
                let cell = board.cell(at: next)
                if !seen[next] && (cell == color || cell == .empty) {
                    seen[next] = true
                    stack.append(next)
                }
            }
        }
    }

    mutating func accept() {
        accepted = true
    }

    /// The owner of every point once the dead stones are off: black, white or empty for neither.
    func territory() -> [Cell] {
        Game.areaOwners(current, dead: dead)
    }

    func count() -> Score {
        var score = Score(komi: komi)
        for owner in territory() {
            if owner == .black {
                score.black += 1
            } else if owner == .white {
                score.white += 1
            }
        }
        return score
    }

    /// Black's margin after scoring or resignation, positive for Black; nothing while the game goes on.
    var margin: Double? {
        guard phase == .finished, let last = moves.last else { return nil }
        if last.isResignation {
            return last.color == .black ? -1000 : 1000
        }
        return count().margin
    }

    var winner: StoneColor? {
        guard let margin, margin != 0 else { return nil }
        return margin > 0 ? .black : .white
    }

    /// "B+3.5", "W+R", "0"; empty while the game goes on.
    var resultText: String {
        guard let margin, let last = moves.last else { return "" }
        if margin == 0 {
            return "0"
        }
        let winner = margin > 0 ? "B" : "W"
        return last.isResignation ? "\(winner)+R" : "\(winner)+\(Go.format(abs(margin)))"
    }

    /// The owner of every point with the dead stones taken off: the stones' color, the color that alone surrounds an
    /// empty region, or empty for neither.
    static func areaOwners(_ board: Board, dead: [Bool]) -> [Cell] {
        var cells = [Cell](repeating: .empty, count: Go.pointCount)
        var owner = [Cell](repeating: .empty, count: Go.pointCount)
        for point in 0..<Go.pointCount {
            cells[point] = dead[point] ? .empty : board.cell(at: point)
        }
        var seen = [Bool](repeating: false, count: Go.pointCount)
        var region: [GoPoint] = []
        var stack: [GoPoint] = []
        for point in 0..<Go.pointCount {
            let cell = cells[point]
            if cell.isStone {
                owner[point] = cell
                continue
            }
            if cell != .empty || seen[point] {
                continue
            }
            // An empty region: whose stones it touches.
            var black = false, white = false
            region.removeAll(keepingCapacity: true)
            stack = [point]
            seen[point] = true
            while let at = stack.popLast() {
                region.append(at)
                for direction in 0..<4 {
                    let next = Go.neighbour(at, direction)
                    let around = cells[next]
                    black = black || around == .black
                    white = white || around == .white
                    if around == .empty && !seen[next] {
                        seen[next] = true
                        stack.append(next)
                    }
                }
            }
            if black != white {
                for at in region {
                    owner[at] = black ? .black : .white
                }
            }
        }
        return owner
    }
}

// MARK: - Game records

extension Game {
    /// The game in SGF, with the setup stones, the moves and the result.
    func sgf(blackName: String, whiteName: String, date: Date = Date()) -> String {
        let day = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        func twoDigits(_ value: Int?) -> String { value.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "01" }
        var sgf = "(;GM[1]FF[4]CA[UTF-8]AP[3D Go:1.0]SZ[\(size)]KM[\(Go.format(komi))]RU[Chinese]"
        sgf += "DT[\(day.year ?? 2026)-\(twoDigits(day.month))-\(twoDigits(day.day))]"
        if !blackName.isEmpty {
            sgf += "PB[\(SgfReader.escape(blackName))]"
        }
        if !whiteName.isEmpty {
            sgf += "PW[\(SgfReader.escape(whiteName))]"
        }
        if handicap > 0 {
            sgf += "HA[\(handicap)]"
        }
        // The stones on the board at the start.
        var black = "", white = ""
        for point in 0..<Go.pointCount {
            switch start.cell(at: point) {
            case .black: black += "[\(SgfReader.point(point))]"
            case .white: white += "[\(SgfReader.point(point))]"
            default: break
            }
        }
        if !black.isEmpty {
            sgf += "AB" + black
        }
        if !white.isEmpty {
            sgf += "AW" + white
        }
        if start.toPlay == .white {
            sgf += "PL[W]"
        }
        let result = resultText
        if !result.isEmpty {
            sgf += "RE[\(result)]"
        }
        var count = 0
        for record in moves where !record.isResignation {
            count += 1
            sgf += "\(count % 10 == 0 ? "\n" : "");\(record.color == .black ? "B" : "W")[\(SgfReader.point(record.point))]"
        }
        return sgf + ")\n"
    }

    /// An SGF game: its main line, with the size, komi, handicap and setup stones. Whatever comes before the game,
    /// such as a message it was pasted from, is skipped.
    static func fromSgf(_ text: String) throws(GameRecordError) -> Game {
        let bytes = Array(text.utf8)
        guard let begin = SgfReader.find(Array("(;".utf8), in: bytes) else { throw GameRecordError("no SGF game") }
        var reader = SgfReader(Array(bytes[begin...]))
        let nodes = try reader.mainLine()
        guard let root = nodes.first else { throw GameRecordError("an empty game") }

        var size = 19
        if let value = root.value("SZ") {
            size = Int(atoi(value))
        }
        guard size >= 2 && size <= Go.maxSize else { throw GameRecordError("a board of \(size) is not supported") }
        var handicap = 0
        if let value = root.value("HA") {
            handicap = max(0, Int(atoi(value)))
        }
        var komi = handicap >= 2 ? 0.5 : 7.5
        if let value = root.value("KM") {
            komi = atof(value)
        }

        // The setup stones, or the usual handicap when none are given.
        var start = Board(size: size)
        var setup = false
        for (name, color) in [("AB", StoneColor.black), ("AW", StoneColor.white)] {
            for value in root.values(name) {
                for point in SgfReader.points(value, size: size) where start.cell(at: point) == .empty && start.isLegal(point, color) {
                    start.setup(point, color)
                    setup = true
                }
            }
        }
        if !setup && handicap >= 2 {
            for point in Go.handicapPoints(size: size, stones: handicap) {
                start.setup(point, .black)
            }
        }
        if handicap >= 2 {
            start.setToPlay(.white)
        }
        if let value = root.value("PL") {
            start.setToPlay(value == "W" || value == "w" ? .white : .black)
        }

        var game = Game()
        game.begin(start, handicap: handicap, komi: komi)
        var number = 0
        for node in nodes {
            for (name, color) in [("B", StoneColor.black), ("W", StoneColor.white)] {
                guard let value = node.value(name) else { continue }
                number += 1
                guard game.phase == .playing else { throw GameRecordError("move \(number) comes after the end") }
                // A move out of turn: the other side passed.
                if game.current.toPlay != color {
                    game.push(Go.pass, color.opposite)
                }
                var point = Go.pass
                if !value.isEmpty && !(value == "tt" && size <= 19) {
                    let points = SgfReader.points(value, size: size)
                    guard points.count == 1 else { throw GameRecordError("move \(number) is not a point") }
                    point = points[0]
                }
                guard game.isLegal(point) else {
                    throw GameRecordError("move \(number) (\(Go.name(point, size: size))) is not legal")
                }
                game.push(point, color)
            }
        }
        if let result = root.value("RE") {
            let characters = Array(result.utf8)
            if characters.count >= 3 && characters[1] == UInt8(ascii: "+") && characters[2] == UInt8(ascii: "R") && game.phase == .playing {
                // The side that lost resigned.
                let winner = characters[0] | 0x20 // lowercase
                game.push(Go.resignation, winner == UInt8(ascii: "b") ? .white : .black)
            }
        }
        game.redoMoves.removeAll()
        return game
    }
}

struct GameRecordError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

