/// Where each point was first played in a simulation, and by whom, for the all-moves-as-first statistics.
struct FirstMoves {
    var ply = [Int16](repeating: -1, count: Go.pointCount)
    var color = [StoneColor](repeating: .black, count: Go.pointCount)

    mutating func clear() {
        for index in ply.indices {
            ply[index] = -1
        }
    }

    mutating func record(_ point: GoPoint, by side: StoneColor, at moment: Int) {
        if point != Go.pass && ply[point] < 0 {
            ply[point] = Int16(moment)
            color[point] = side
        }
    }
}

/// Plays a position out to the end with the usual heuristics of Go programs: answers to the last move first (taking
/// a string in atari, saving one's own, good 3×3 shapes), then any move that does not fill an eye of one's own or
/// put a string in atari for nothing.
struct Playout {
    var random: FastRandom
    private let shapeTable = ShapeTable.table
    private var moves = [GoPoint](repeating: Go.pass, count: 48)
    private var count = 0

    init(seed: UInt64) {
        random = FastRandom(seed: seed)
    }

    /// A move for the side to play.
    mutating func choose(_ board: Board) -> GoPoint {
        let me = board.toPlay
        let last = board.lastMove
        if last != Go.pass && board.isStone(last) {
            if random.below(10) < 9 && tactics(board, last, me) {
                return pick()
            }
            if random.below(10) < 9 && matchShapes(board, last, me) {
                return pick()
            }
        }
        let empty = board.emptyCount
        if empty == 0 {
            return Go.pass
        }
        var index = random.below(empty)
        for _ in 0..<empty {
            if index == empty {
                index = 0
            }
            let point = board.emptyPoint(index)
            index += 1
            if !board.isLegal(point, me) || board.isEye(point, me) {
                continue
            }
            // Putting a string in atari for nothing is left out; a single stone now and then, as a throw-in.
            if board.isSelfAtari(point, me) && (joinsString(board, point, me) || random.below(10) < 8) {
                continue
            }
            return point
        }
        return Go.pass
    }

    /// Plays the position out to the end, both sides passing; Black's score less komi.
    mutating func run(_ board: inout Board, komi: Double) -> Double {
        playOut(&board, komi: komi, ply: 0) { _, _, _ in }
    }

    /// The same, recording where each point was first played, counting the moves from `ply`.
    mutating func run(_ board: inout Board, komi: Double, recording first: inout FirstMoves, ply: Int) -> Double {
        playOut(&board, komi: komi, ply: ply) { first.record($0, by: $1, at: $2) }
    }

    private mutating func playOut(_ board: inout Board, komi: Double, ply start: Int, onMove: (GoPoint, StoneColor, Int) -> Void) -> Double {
        let limit = board.size * board.size * 3
        var passes = 0
        var ply = start
        var moves = 0
        while moves < limit && passes < 2 {
            let me = board.toPlay
            let move = choose(board)
            onMove(move, me, ply)
            board.play(move, me)
            passes = move == Go.pass ? passes + 1 : 0
            ply += 1
            moves += 1
        }
        return Double(board.quickScore()) - komi
    }

    private func joinsString(_ board: Board, _ point: GoPoint, _ me: StoneColor) -> Bool {
        let own = me.cell
        for direction in 0..<4 where board.cell(at: Go.neighbour(point, direction)) == own {
            return true
        }
        return false
    }

    private mutating func add(_ board: Board, _ point: GoPoint, _ me: StoneColor) {
        if count < moves.count && board.isLegal(point, me) {
            moves[count] = point
            count += 1
        }
    }

    private mutating func pick() -> GoPoint { moves[random.below(count)] }

    /// Taking a string in atari next to the last move, or saving one's own.
    private mutating func tactics(_ board: Board, _ last: GoPoint, _ me: StoneColor) -> Bool {
        count = 0
        let own = me.cell
        if board.inAtari(last) {
            add(board, board.atariLiberty(last), me)
        }
        for direction in 0..<4 {
            let next = Go.neighbour(last, direction)
            guard board.isStone(next) && board.inAtari(next) else { continue }
            if board.cell(at: next) != own {
                add(board, board.atariLiberty(next), me)
                continue
            }
            // Our string in atari: run, if that gives it liberties, or take a string of theirs touching it.
            let liberty = board.atariLiberty(next)
            if !board.isSelfAtari(liberty, me) {
                add(board, liberty, me)
            }
            let head = board.head(of: next)
            var stone = head
            for _ in 0..<12 {
                for direction in 0..<4 {
                    let enemy = Go.neighbour(stone, direction)
                    if board.isStone(enemy) && board.cell(at: enemy) != own && board.inAtari(enemy) {
                        add(board, board.atariLiberty(enemy), me)
                    }
                }
                stone = board.nextStone(stone)
                if stone == head {
                    break
                }
            }
        }
        return count > 0
    }

    /// The shapes round the last move.
    private mutating func matchShapes(_ board: Board, _ last: GoPoint, _ me: StoneColor) -> Bool {
        count = 0
        for slot in 0..<8 {
            let point = ShapeTable.around(last, slot)
            if board.cell(at: point) == .empty && ShapeTable.matches(shapeTable, board, point, me) && !board.isSelfAtari(point, me) {
                add(board, point, me)
            }
        }
        return count > 0
    }
}

/// Who owns each point at the end of a playout: its stone's color, or the color of all the stones round an empty point.
func countOwners(_ board: Board, black: inout [UInt32], white: inout [UInt32]) {
    let size = board.size
    for y in 0..<size {
        for x in 0..<size {
            let point = Go.point(x, y)
            var owner = board.cell(at: point)
            if owner == .empty {
                var b = false, w = false
                for direction in 0..<4 {
                    let cell = board.cell(at: Go.neighbour(point, direction))
                    b = b || cell == .black
                    w = w || cell == .white
                }
                owner = b == w ? .empty : b ? .black : .white
            }
            if owner == .black {
                black[point] += 1
            } else if owner == .white {
                white[point] += 1
            }
        }
    }
}
