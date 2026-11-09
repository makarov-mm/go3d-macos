/// What the trees of the threads have found out at the root, added up at the end of a search.
struct RootStats: Sendable {
    var visits: [Double]
    var wins: [Double]
    var black = [UInt32](repeating: 0, count: Go.pointCount)
    var white = [UInt32](repeating: 0, count: Go.pointCount)
    var playouts: UInt64 = 0

    init(moves: Int) {
        visits = [Double](repeating: 0, count: moves)
        wins = visits
    }
}

/// A Monte Carlo search tree with priors and all-moves-as-first (RAVE) statistics.
struct SearchTree {
    private struct Node {
        var move = Int16(Go.pass)
        var childCount: Int16 = 0
        var firstChild: Int32 = -1 // -1 until the node is expanded
        var visits: Float = 0      // for the side that played the move, the prior knowledge included
        var wins: Float = 0
        var raveVisits: Float = 0
        var raveWins: Float = 0
        var simulations: UInt32 = 0 // through the node itself
    }

    private static let equivalence: Float = 3000 // how long the all-moves-as-first statistics weigh in
    private static let expandAfter: UInt32 = 8    // simulations
    private static let maxNodes = 2_000_000

    private let root: Board
    private let komi: Double
    private let shapes = ShapeTable.table
    private var playout: Playout
    private var nodes: [Node] = []
    private var path: [Int] = []
    private var first = FirstMoves()

    init(root: Board, moves: [GoPoint], komi: Double, seed: UInt64) {
        self.root = root
        self.komi = komi
        playout = Playout(seed: seed)
        nodes.reserveCapacity(min(Self.maxNodes, 4096 + moves.count))
        nodes.append(Node(childCount: Int16(moves.count), firstChild: 1))
        for move in moves {
            var child = Node()
            child.move = Int16(move)
            Self.setPrior(&child, root, move, root.toPlay, shapes)
            nodes.append(child)
        }
    }

    mutating func simulate(_ stats: inout RootStats) {
        var board = root
        let rootColor = root.toPlay
        first.clear()
        path.removeAll(keepingCapacity: true)
        path.append(0)
        var node = 0, ply = 0
        while nodes[node].firstChild >= 0 && board.passes < 2 {
            node = select(node)
            let move = Int(nodes[node].move)
            first.record(move, by: board.toPlay, at: ply)
            ply += 1
            board.play(move, board.toPlay)
            path.append(node)
            // A leaf that has been visited enough grows its children.
            if nodes[node].firstChild < 0 && nodes[node].simulations >= Self.expandAfter && board.passes < 2 {
                expand(node, board)
            }
        }
        let score = board.passes >= 2 ? Double(board.quickScore()) - komi : playout.run(&board, komi: komi, recording: &first, ply: ply)
        let blackWins = score > 0
        countOwners(board, black: &stats.black, white: &stats.white)
        stats.playouts += 1

        // Back up the result, and the all-moves-as-first results to the brothers of each node on the way.
        var depth = path.count
        while depth > 0 {
            depth -= 1
            let index = path[depth]
            let mover: StoneColor = depth % 2 == 0 ? rootColor.opposite : rootColor
            nodes[index].visits += 1
            nodes[index].wins += (mover == .black) == blackWins ? 1 : 0
            nodes[index].simulations += 1
            let toPlay = mover.opposite
            let result: Float = (toPlay == .black) == blackWins ? 1 : 0
            let firstChild = Int(nodes[index].firstChild)
            for child in firstChild..<firstChild + Int(nodes[index].childCount) {
                let at = Int(nodes[child].move)
                if at != Go.pass && Int(first.ply[at]) >= depth && first.color[at] == toPlay {
                    nodes[child].raveVisits += 1
                    nodes[child].raveWins += result
                }
            }
        }
    }

    func collect(_ stats: inout RootStats) {
        let root = nodes[0]
        for i in 0..<Int(root.childCount) {
            let child = nodes[Int(root.firstChild) + i]
            stats.visits[i] += Double(child.visits)
            stats.wins[i] += Double(child.wins)
        }
    }

    private func select(_ parent: Int) -> Int {
        let node = nodes[parent]
        var best = Int(node.firstChild)
        var bestValue: Float = -1
        for index in Int(node.firstChild)..<Int(node.firstChild) + Int(node.childCount) {
            let child = nodes[index]
            var value = child.wins / child.visits
            if child.raveVisits > 0 {
                let beta = child.raveVisits / (child.visits + child.raveVisits + child.visits * child.raveVisits / Self.equivalence)
                value = (1 - beta) * value + beta * (child.raveWins / child.raveVisits)
            }
            if value > bestValue {
                bestValue = value
                best = index
            }
        }
        return best
    }

    private mutating func expand(_ index: Int, _ board: Board) {
        if nodes.count + board.emptyCount + 1 > Self.maxNodes {
            return
        }
        let me = board.toPlay
        let first = nodes.count
        for i in 0..<board.emptyCount {
            let point = board.emptyPoint(i)
            if !board.isLegal(point, me) || board.isEye(point, me) {
                continue
            }
            var child = Node()
            child.move = Int16(point)
            Self.setPrior(&child, board, point, me, shapes)
            nodes.append(child)
        }
        if nodes.count == first {
            var pass = Node()
            Self.setPrior(&pass, board, Go.pass, me, shapes)
            nodes.append(pass)
        }
        nodes[index].firstChild = Int32(first)
        nodes[index].childCount = Int16(nodes.count - first)
    }

    /// Prior knowledge of a move, as visits and wins it starts with: captures, escapes and good shapes are favored, as
    /// are lines three and four early on; self-ataris and the first line early on are not.
    private static func setPrior(_ node: inout Node, _ board: Board, _ point: GoPoint, _ me: StoneColor, _ shapes: [UInt8]) {
        var visits: Float = 10, wins: Float = 5
        func good(_ weight: Float) {
            visits += weight / 2
            wins += weight / 2
        }
        func bad(_ weight: Float) {
            visits += weight / 2
        }
        defer {
            node.visits = visits
            node.wins = wins
        }
        if point == Go.pass {
            return
        }
        let own = me.cell
        for direction in 0..<4 {
            let next = Go.neighbour(point, direction)
            if board.isStone(next) && board.inAtari(next) {
                if board.cell(at: next) != own {
                    good(board.stoneCount(next) > 1 ? 30 : 15)
                } else if !board.isSelfAtari(point, me) {
                    good(15)
                }
            }
        }
        if board.isSelfAtari(point, me) {
            let joins = (0..<4).contains { board.cell(at: Go.neighbour(point, $0)) == own }
            bad(joins ? 30 : 10) // a lone stone may be a throw-in
        }
        let last = board.lastMove
        if last != Go.pass && board.isStone(last) {
            let dx = abs(Go.x(point) - Go.x(last)), dy = abs(Go.y(point) - Go.y(last))
            if dx <= 1 && dy <= 1 && ShapeTable.matches(shapes, board, point, me) {
                good(10)
            } else if dx + dy <= 3 {
                good(4)
            }
        }
        // Early on, the third and fourth lines, the corners first; not the edges.
        let size = board.size
        let x = Go.x(point), y = Go.y(point)
        let line = 1 + min(x, y, size - 1 - x, size - 1 - y)
        if board.emptyCount > size * size * 3 / 4 {
            if line == 1 {
                bad(30)
            } else if line == 2 {
                bad(20)
            } else if line == 3 || (line == 4 && size >= 13) {
                good(12)
            }
            // A corner point while the corner is empty.
            let fromSide = min(x, size - 1 - x), fromTop = min(y, size - 1 - y)
            if size >= 13 && (2...3).contains(fromSide) && (2...3).contains(fromTop) {
                let cornerX = x < size / 2 ? 0 : size - 6, cornerY = y < size / 2 ? 0 : size - 6
                var empty = true
                for dy in 0..<6 where empty {
                    for dx in 0..<6 where empty {
                        empty = board.cell(at: Go.point(cornerX + dx, cornerY + dy)) == .empty
                    }
                }
                if empty {
                    good(20)
                }
            }
        } else if line == 1 {
            bad(5)
        }
    }
}
