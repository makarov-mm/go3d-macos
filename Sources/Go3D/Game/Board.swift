/// The board with its strings of stones and their liberties, kept up to date move by move; the legality of moves
/// with simple ko; and the moves themselves, with the stones they take.
///
/// The per-point tables live in one block of memory shared between copies until one of them changes, so that a
/// board is cheap to copy, as the computer player does for every simulation.
struct Board: Sendable {
    private(set) var size: Int
    private var storage: Storage
    private(set) var toPlay: StoneColor = .black
    /// The point that simple ko forbids, or `Go.pass`.
    private(set) var ko: GoPoint = Go.pass
    private(set) var lastMove: GoPoint = Go.pass
    /// Passes in a row, at the end of the moves so far.
    private(set) var passes = 0
    /// Of the stones alone.
    private(set) var hash: UInt64 = 0
    private(set) var emptyCount = 0
    private var blackCaptures = 0
    private var whiteCaptures = 0

    init(size: Int = 19) {
        self.size = min(max(size, 2), Go.maxSize)
        storage = Storage()
        let cells = storage.values
        for point in 0..<Go.pointCount {
            cells[point] = Code.border
        }
        for y in 0..<self.size {
            for x in 0..<self.size {
                let point = Go.point(x, y)
                cells[point] = Code.empty
                addEmpty(point)
            }
        }
    }

    // MARK: Reading the position

    func cell(at point: GoPoint) -> Cell { Cell(code: Int(storage.values[point])) }
    /// The cell as its raw code, 0 to 3 in the order of `Cell`.
    func code(at point: GoPoint) -> Int { Int(storage.values[point]) }
    func isStone(_ point: GoPoint) -> Bool { isStoneCode(storage.values[point]) }
    func isOnBoard(_ point: GoPoint) -> Bool { point > 0 && point < Go.pointCount && storage.values[point] != Code.border }
    func captures(by color: StoneColor) -> Int { color == .black ? blackCaptures : whiteCaptures }
    func emptyPoint(_ index: Int) -> GoPoint { Int(storage.values[Storage.empty + index]) }

    /// The string of stones through a point: its first stone, its size, and the stones in a ring.
    func head(of point: GoPoint) -> GoPoint { Int(storage.values[Storage.head + point]) }
    func nextStone(_ point: GoPoint) -> GoPoint { Int(storage.values[Storage.next + point]) }
    func stoneCount(_ point: GoPoint) -> Int { Int(storage.values[Storage.stones + head(of: point)]) }

    /// The string through a point has a single liberty left. Each string keeps its pseudo-liberties (an empty
    /// neighbour counted once for every stone it touches) with their sum and the sum of their squares: when all of
    /// them are the same point, the string is in atari.
    func inAtari(_ point: GoPoint) -> Bool {
        let values = storage.values
        let head = Int(values[Storage.head + point])
        let libs = Int(values[Storage.libs + head])
        let sum = Int(values[Storage.libSum + head])
        return libs > 0 && libs * Int(values[Storage.libSumSquares + head]) == sum * sum
    }

    /// The last liberty of a string in atari.
    func atariLiberty(_ point: GoPoint) -> GoPoint {
        let values = storage.values
        let head = Int(values[Storage.head + point])
        return Int(values[Storage.libSum + head] / values[Storage.libs + head])
    }

    /// Legal by the rules but superko: on an empty point, not retaking a ko at once, and not suicide.
    func isLegal(_ point: GoPoint, _ color: StoneColor) -> Bool {
        if point == Go.pass {
            return true
        }
        let cells = storage.values
        guard isOnBoard(point), cells[point] == Code.empty, point != ko else { return false }
        let own = Code.of(color)
        for direction in 0..<4 {
            let next = Go.neighbour(point, direction)
            let cell = cells[next]
            if cell == Code.empty {
                return true
            }
            if cell == Code.border {
                continue
            }
            // A string of one's own with another liberty, or one of the other side's that the move takes.
            if (cell == own) != inAtari(next) {
                return true
            }
        }
        return false
    }

    /// An eye of `color` that playouts leave alone: surrounded by its stones, the corners mostly too.
    func isEye(_ point: GoPoint, _ color: StoneColor) -> Bool {
        let cells = storage.values
        let own = Code.of(color), other = Code.of(color.opposite)
        var edge = false
        for direction in 0..<4 {
            let cell = cells[Go.neighbour(point, direction)]
            if cell == Code.border {
                edge = true
            } else if cell != own {
                return false
            }
        }
        var enemies = 0
        for direction in 0..<4 where cells[Go.diagonal(point, direction)] == other {
            enemies += 1
        }
        return enemies < (edge ? 1 : 2)
    }

    /// The move would leave its string with a single liberty, and takes nothing.
    func isSelfAtari(_ point: GoPoint, _ color: StoneColor) -> Bool {
        let values = storage.values
        let own = Code.of(color)
        // Up to two liberties other than the point itself; finding two is enough.
        var first = -1
        func add(_ liberty: GoPoint) -> Bool {
            if liberty == point || liberty == first {
                return false
            }
            if first < 0 {
                first = liberty
                return false
            }
            return true
        }
        for direction in 0..<4 where values[Go.neighbour(point, direction)] == Code.empty {
            if add(Go.neighbour(point, direction)) {
                return false
            }
        }
        for direction in 0..<4 {
            let next = Go.neighbour(point, direction)
            let cell = values[next]
            guard isStoneCode(cell) else { continue }
            if cell != own {
                if inAtari(next) {
                    return false // it takes the string, and gains a liberty where it stood
                }
                continue
            }
            let head = Int(values[Storage.head + next])
            var stone = head
            repeat {
                for direction in 0..<4 where values[Go.neighbour(stone, direction)] == Code.empty {
                    if add(Go.neighbour(stone, direction)) {
                        return false
                    }
                }
                stone = Int(values[Storage.next + stone])
            } while stone != head
        }
        return true
    }

    /// Black's points less White's, counting stones and the empty points next only to stones of one color: the score
    /// at the end of a playout, where every empty point is a single eye or a shared liberty.
    func quickScore() -> Int {
        let cells = storage.values
        var score = 0
        for y in 0..<size {
            for x in 0..<size {
                let point = Go.point(x, y)
                switch cells[point] {
                case Code.black:
                    score += 1
                case Code.white:
                    score -= 1
                default:
                    var black = false, white = false
                    for direction in 0..<4 {
                        let cell = cells[Go.neighbour(point, direction)]
                        black = black || cell == Code.black
                        white = white || cell == Code.white
                    }
                    score += black == white ? 0 : black ? 1 : -1
                }
            }
        }
        return score
    }

    // MARK: Changing the position

    mutating func setToPlay(_ color: StoneColor) {
        toPlay = color
    }

    /// A legal move or a pass. Returns the stones taken when `recordCaptures` is set.
    @discardableResult
    mutating func play(_ point: GoPoint, _ color: StoneColor, recordCaptures: Bool = false) -> [GoPoint] {
        ko = Go.pass
        toPlay = color.opposite
        lastMove = point
        if point == Go.pass {
            passes += 1
            return []
        }
        passes = 0
        makeUnique()

        let values = storage.values
        let own = Code.of(color), other = Code.of(color.opposite)
        removeEmpty(point)
        values[point] = own
        hash ^= Zobrist.key(point, color)
        values[Storage.head + point] = Int32(point)
        values[Storage.next + point] = Int32(point)
        values[Storage.stones + point] = 1
        values[Storage.libs + point] = 0
        values[Storage.libSum + point] = 0
        values[Storage.libSumSquares + point] = 0
        for direction in 0..<4 {
            let next = Go.neighbour(point, direction)
            if values[next] == Code.empty {
                addLiberty(head: point, liberty: next)
            } else if isStoneCode(values[next]) {
                removeLiberty(head: head(of: next), liberty: point)
            }
        }
        for direction in 0..<4 {
            let next = Go.neighbour(point, direction)
            if values[next] == own && head(of: next) != head(of: point) {
                merge(head(of: point), head(of: next))
            }
        }

        var captured: [GoPoint] = []
        var taken = 0
        var lastTaken = Go.pass
        for direction in 0..<4 {
            let next = Go.neighbour(point, direction)
            if values[next] == other && values[Storage.libs + head(of: next)] == 0 {
                lastTaken = next
                taken += removeString(head: head(of: next), record: recordCaptures, into: &captured)
            }
        }
        if color == .black {
            blackCaptures += taken
        } else {
            whiteCaptures += taken
        }
        // One stone taken by a lone stone that is left with that point as its only liberty: a ko.
        let head = head(of: point)
        if taken == 1 && values[Storage.stones + head] == 1 && values[Storage.libs + head] == 1 {
            ko = lastTaken
        }
        return captured
    }

    /// A stone set on the board before the game, such as a handicap stone.
    mutating func setup(_ point: GoPoint, _ color: StoneColor) {
        let side = toPlay
        play(point, color)
        toPlay = side
        lastMove = Go.pass
        ko = Go.pass
    }

    // MARK: Strings and liberties

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(copying: storage)
        }
    }

    private mutating func addEmpty(_ point: GoPoint) {
        let values = storage.values
        values[Storage.emptyIndex + point] = Int32(emptyCount)
        values[Storage.empty + emptyCount] = Int32(point)
        emptyCount += 1
    }

    private mutating func removeEmpty(_ point: GoPoint) {
        let values = storage.values
        let index = Int(values[Storage.emptyIndex + point])
        emptyCount -= 1
        let last = values[Storage.empty + emptyCount]
        values[Storage.empty + index] = last
        values[Storage.emptyIndex + Int(last)] = Int32(index)
    }

    private func addLiberty(head: GoPoint, liberty: GoPoint) {
        let values = storage.values
        values[Storage.libs + head] &+= 1
        values[Storage.libSum + head] &+= Int32(liberty)
        values[Storage.libSumSquares + head] &+= Int32(liberty * liberty)
    }

    private func removeLiberty(head: GoPoint, liberty: GoPoint) {
        let values = storage.values
        values[Storage.libs + head] &-= 1
        values[Storage.libSum + head] &-= Int32(liberty)
        values[Storage.libSumSquares + head] &-= Int32(liberty * liberty)
    }

    /// Joins two strings, the smaller into the larger.
    private func merge(_ first: GoPoint, _ second: GoPoint) {
        let values = storage.values
        var a = first, b = second
        if values[Storage.stones + a] < values[Storage.stones + b] {
            swap(&a, &b)
        }
        var stone = b
        repeat {
            values[Storage.head + stone] = Int32(a)
            stone = Int(values[Storage.next + stone])
        } while stone != b
        let nextOfA = values[Storage.next + a]
        values[Storage.next + a] = values[Storage.next + b]
        values[Storage.next + b] = nextOfA
        values[Storage.stones + a] &+= values[Storage.stones + b]
        values[Storage.libs + a] &+= values[Storage.libs + b]
        values[Storage.libSum + a] &+= values[Storage.libSum + b]
        values[Storage.libSumSquares + a] &+= values[Storage.libSumSquares + b]
    }

    private mutating func removeString(head: GoPoint, record: Bool, into captured: inout [GoPoint]) -> Int {
        let values = storage.values
        let color: StoneColor = values[head] == Code.black ? .black : .white
        var count = 0
        var stone = head
        repeat {
            values[stone] = Code.empty
            hash ^= Zobrist.key(stone, color)
            addEmpty(stone)
            if record {
                captured.append(stone)
            }
            count += 1
            stone = Int(values[Storage.next + stone])
        } while stone != head
        // The points freed are liberties again of the strings round them.
        repeat {
            for direction in 0..<4 {
                let next = Go.neighbour(stone, direction)
                if isStoneCode(values[next]) {
                    addLiberty(head: self.head(of: next), liberty: stone)
                }
            }
            stone = Int(values[Storage.next + stone])
        } while stone != head
        return count
    }

    private func isStoneCode(_ code: Int32) -> Bool { code == Code.black || code == Code.white }
}

// MARK: - Storage

extension Board {
    /// The cells as stored, in the order of `Cell`.
    fileprivate enum Code {
        static var empty: Int32 { 0 }
        static var black: Int32 { 1 }
        static var white: Int32 { 2 }
        static var border: Int32 { 3 }

        static func of(_ color: StoneColor) -> Int32 { color == .black ? black : white }
    }

    /// All the tables of a board in one block: the cells; for each stone the head of its string and the next stone
    /// in its ring; at each head the string's stones and pseudo-liberties with their sum and sum of squares; and the
    /// list of empty points with each one's place in it.
    fileprivate final class Storage: @unchecked Sendable {
        // Where each table begins, the cells first.
        static var head: Int { 441 }
        static var next: Int { 2 * 441 }
        static var stones: Int { 3 * 441 }
        static var libs: Int { 4 * 441 }
        static var libSum: Int { 5 * 441 }
        static var libSumSquares: Int { 6 * 441 }
        static var emptyIndex: Int { 7 * 441 }
        static var empty: Int { 8 * 441 }
        static var count: Int { 8 * 441 + 361 }

        let values: UnsafeMutablePointer<Int32>

        init() {
            values = .allocate(capacity: Self.count)
            values.initialize(repeating: 0, count: Self.count)
        }

        init(copying other: Storage) {
            values = .allocate(capacity: Self.count)
            values.initialize(from: other.values, count: Self.count)
        }

        deinit {
            values.deallocate()
        }
    }
}

// MARK: - Hashing

/// A random number for each color on each point, for the hash of a position: the outputs of SplitMix64 seeded with
/// 0x5EED, Black's points first. The nth output is worked out directly, so there is no table to look up.
enum Zobrist {
    @inline(__always)
    static func key(_ point: GoPoint, _ color: StoneColor) -> UInt64 {
        let n = UInt64(color.index * Go.pointCount + point + 1)
        var z = 0x5EED &+ n &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
