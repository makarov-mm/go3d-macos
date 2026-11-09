import Foundation

struct SearchLimits: Sendable {
    var playouts = 10000 // in all, over the threads
    var milliseconds = 2000
    var threads = 1
    var mayResign = true
    var seed: UInt64 = 0
}

struct SearchResult: Sendable {
    var move = Go.pass
    var resign = false
    var winRate = 0.5 // for the side to move
    var playouts = 0
}

/// Who owns each point at the end of the game, as the share of playouts in which Black did, and the mean score.
struct Ownership: Sendable {
    var black = [Float](repeating: 0, count: Go.pointCount)
    /// Black's points less White's and komi.
    var margin = 0.0

    /// The stones that are probably dead, for scoring.
    func dead(on board: Board) -> [Bool] {
        (0..<Go.pointCount).map { point in
            let share = black[point]
            let cell = board.cell(at: point)
            return (cell == .black && share < 0.5) || (cell == .white && share > 0.5)
        }
    }
}

/// The computer player: Monte Carlo tree search with playouts that follow the usual heuristics of Go programs, a tree
/// with priors and all-moves-as-first statistics, and independent trees on several threads whose results are added up.
enum Engine {
    /// The move for the side to move; `history` holds the earlier positions, for superko.
    static func search(_ board: Board, history: [UInt64], komi: Double, limits: SearchLimits, stop: StopFlag) -> SearchResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(limits.milliseconds))
        let me = board.toPlay

        // The moves at the root: legal, superko included, and not into one's own eyes.
        var moves: [GoPoint] = []
        for index in 0..<board.emptyCount {
            let point = board.emptyPoint(index)
            if !board.isLegal(point, me) || board.isEye(point, me) {
                continue
            }
            var next = board
            next.play(point, me)
            if !history.contains(next.hash) {
                moves.append(point)
            }
        }
        var result = SearchResult()
        if moves.isEmpty {
            return result // a pass
        }

        // On the big boards the first stones go to the empty corners, which the playouts do not see the worth of.
        let opening = openingMove(board, seed: limits.seed)
        if opening != Go.pass && moves.contains(opening) {
            result.move = opening
            return result
        }

        // Independent trees, one for each thread, their visits added up at the end.
        let threads = min(max(limits.threads, 1), 16)
        let share = max(1, limits.playouts / threads)
        let slots = ResultSlots<RootStats>(count: threads)
        let rootMoves = moves
        DispatchQueue.concurrentPerform(iterations: threads) { index in
            var own = RootStats(moves: rootMoves.count)
            var tree = SearchTree(root: board, moves: rootMoves, komi: komi,
                                  seed: limits.seed &* 7919 &+ UInt64(index) &* 104_729 &+ 1)
            for n in 0..<share {
                if n & 15 == 0 && (stop.isSet || clock.now >= deadline) {
                    break
                }
                tree.simulate(&own)
            }
            tree.collect(&own)
            slots.store(own, at: index)
        }

        var total = RootStats(moves: moves.count)
        for stats in slots.values() {
            for i in 0..<moves.count {
                total.visits[i] += stats.visits[i]
                total.wins[i] += stats.wins[i]
            }
            for point in 0..<Go.pointCount {
                total.black[point] += stats.black[point]
                total.white[point] += stats.white[point]
            }
            total.playouts += stats.playouts
        }
        var best = 0
        for i in 1..<moves.count where total.visits[i] > total.visits[best] {
            best = i
        }
        result.move = moves[best]
        result.winRate = total.wins[best] / max(1.0, total.visits[best])
        result.playouts = Int(total.playouts)

        if total.playouts > 0 {
            // With every point settled, one way or the other or for neither, there is nothing left to play for: pass.
            let size = board.size
            let n = Double(total.playouts)
            var settled = true
            for y in 0..<size where settled {
                for x in 0..<size where settled {
                    let at = Go.point(x, y)
                    let black = Double(total.black[at]) / n, white = Double(total.white[at]) / n
                    settled = black > 0.85 || white > 0.85 || black + white < 0.15
                }
            }
            if settled {
                result.move = Go.pass
            }

            // The other side has passed: if the game ending now would be won, with the stones that the playouts
            // mostly lose taken off as dead, pass too.
            if board.passes > 0 {
                let dead = (0..<Go.pointCount).map { point in
                    let cell = board.cell(at: point)
                    return (cell == .black && Double(total.white[point]) > n / 2) || (cell == .white && Double(total.black[point]) > n / 2)
                }
                var margin = 0
                for owner in Game.areaOwners(board, dead: dead) {
                    margin += owner == .black ? 1 : owner == .white ? -1 : 0
                }
                if (me == .black) == (Double(margin) - komi > 0) {
                    result.move = Go.pass
                }
            }
        }
        // Hopeless, with enough of the game played to be sure.
        let area = board.size * board.size
        if limits.mayResign && total.playouts >= 2000 && result.winRate < 0.06 && board.emptyCount < area * 2 / 3 {
            result.resign = true
        }
        return result
    }

    /// The position played out many times.
    static func estimate(_ board: Board, komi: Double, playouts: Int, seed: UInt64, stop: StopFlag) -> Ownership {
        var playout = Playout(seed: seed)
        var black = [UInt32](repeating: 0, count: Go.pointCount)
        var white = [UInt32](repeating: 0, count: Go.pointCount)
        var margin = 0.0
        var done = 0
        while done < playouts && !stop.isSet {
            var copy = board
            margin += playout.run(&copy, komi: komi)
            countOwners(copy, black: &black, white: &white)
            done += 1
        }
        var ownership = Ownership()
        let n = Float(max(done, 1))
        for point in 0..<Go.pointCount {
            // The share of Black's ownership, with the points neither owned counted half.
            let neither = Float(done - Int(black[point] + white[point]))
            ownership.black[point] = (Float(black[point]) + 0.5 * neither) / n
        }
        ownership.margin = margin / Double(max(done, 1))
        return ownership
    }

    /// A 4-4, 3-4 or 3-3 point in an empty corner, while there are only a few stones on a board of 13 or more.
    private static func openingMove(_ board: Board, seed: UInt64) -> GoPoint {
        let size = board.size
        guard size >= 13 && board.emptyCount >= size * size - 3 else { return Go.pass }
        var choices: [(point: GoPoint, weight: Int)] = []
        for right in [false, true] {
            for bottom in [false, true] {
                let cornerX = right ? size - 7 : 0, cornerY = bottom ? size - 7 : 0
                var empty = true
                for dy in 0..<7 where empty {
                    for dx in 0..<7 where empty {
                        empty = board.cell(at: Go.point(cornerX + dx, cornerY + dy)) == .empty
                    }
                }
                guard empty else { continue }
                func at(_ x: Int, _ y: Int) -> GoPoint { Go.point(right ? size - 1 - x : x, bottom ? size - 1 - y : y) }
                choices += [(at(3, 3), 4), (at(2, 3), 2), (at(3, 2), 2), (at(2, 2), 1)]
            }
        }
        let total = choices.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return Go.pass }
        var random = FastRandom(seed: seed ^ board.hash)
        var pick = random.below(total)
        for choice in choices {
            if pick < choice.weight {
                return choice.point
            }
            pick -= choice.weight
        }
        return Go.pass
    }
}

/// The results of work spread over threads, one slot for each.
private final class ResultSlots<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [Value?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func store(_ value: Value, at index: Int) {
        lock.withLock { slots[index] = value }
    }

    func values() -> [Value] {
        lock.withLock { slots.compactMap { $0 } }
    }
}
