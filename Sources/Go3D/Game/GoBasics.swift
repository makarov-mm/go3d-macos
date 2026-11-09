// The basic terms of Go on boards of 9×9 to 19×19: the two sides, what lies on a point, and the points
// themselves, named as on a printed board.

/// The two sides.
enum StoneColor: Sendable {
    case black
    case white

    var opposite: StoneColor { self == .black ? .white : .black }
    var index: Int { self == .black ? 0 : 1 }
    var cell: Cell { self == .black ? .black : .white }
}

/// What lies on a point; the border round the board is a point of its own kind.
enum Cell: Sendable {
    case empty
    case black
    case white
    case border

    /// 0 to 3 in the order of the cases, as the board stores cells and the shapes are coded.
    init(code: Int) {
        switch code {
        case 0: self = .empty
        case 1: self = .black
        case 2: self = .white
        default: self = .border
        }
    }

    var code: Int {
        switch self {
        case .empty: 0
        case .black: 1
        case .white: 2
        case .border: 3
        }
    }

    var isStone: Bool { self == .black || self == .white }
}

/// A point of the board: `(y + 1) * stride + x + 1`, for the column `x` from the left and the row `y` from the top,
/// as in SGF. `Go.pass` and `Go.resignation` stand for moves that are not points.
typealias GoPoint = Int

enum Go {
    // Constants as computed properties, so that the hot loops of the playouts read them without any lazy setup.
    static var maxSize: Int { 19 }
    static var stride: Int { 21 }
    static var pointCount: Int { 441 }
    /// A corner of the border, never a point of the board.
    static var pass: GoPoint { 0 }
    /// In a game record.
    static var resignation: GoPoint { -1 }

    /// The four neighbours of a point: above, left, right and below.
    @inline(__always)
    static func neighbour(_ point: GoPoint, _ direction: Int) -> GoPoint {
        switch direction {
        case 0: point - 21
        case 1: point - 1
        case 2: point + 1
        default: point + 21
        }
    }

    /// The four diagonal neighbours of a point.
    @inline(__always)
    static func diagonal(_ point: GoPoint, _ direction: Int) -> GoPoint {
        switch direction {
        case 0: point - 22
        case 1: point - 20
        case 2: point + 20
        default: point + 22
        }
    }

    /// The columns' letters, I left out, as on Go boards.
    static let columns = Array("ABCDEFGHJKLMNOPQRST")

    static func point(_ x: Int, _ y: Int) -> GoPoint { (y + 1) * stride + x + 1 }
    static func x(_ point: GoPoint) -> Int { point % stride - 1 }
    static func y(_ point: GoPoint) -> Int { point / stride - 1 }

    /// "D4": the column's letter and the row counted from the bottom; "pass", "resign".
    static func name(_ point: GoPoint, size: Int) -> String {
        switch point {
        case pass: "pass"
        case resignation: "resign"
        default: "\(columns[x(point)])\(size - y(point))"
        }
    }

    static func parsePoint(_ text: String, size: Int) -> GoPoint? {
        guard let first = text.first, text.count >= 2,
              let column = columns.firstIndex(of: Character(first.uppercased())),
              let row = Int(text.dropFirst()) else { return nil }
        let y = size - row
        guard column < size, y >= 0, y < size else { return nil }
        return point(column, y)
    }

    /// The hoshi of a board.
    static func starPoints(size: Int) -> [GoPoint] {
        let edge = size >= 13 ? 3 : 2, far = size - 1 - edge, middle = size / 2
        var points = [point(edge, edge), point(far, edge), point(edge, far), point(far, far)]
        if size % 2 == 1 {
            points.append(point(middle, middle))
        }
        if size >= 19 {
            points += [point(middle, edge), point(middle, far), point(edge, middle), point(far, middle)]
        }
        return points
    }

    static func maxHandicap(size: Int) -> Int { size >= 13 ? 9 : 5 }

    /// The points where handicap stones go, in the order they are placed: the corners, upper right and lower left
    /// first, then the middle and the sides.
    static func handicapPoints(size: Int, stones: Int) -> [GoPoint] {
        let edge = size >= 13 ? 3 : 2, far = size - 1 - edge, middle = size / 2
        var points = [point(far, edge), point(edge, far), point(far, far), point(edge, edge)]
        if stones >= 6 {
            points += [point(edge, middle), point(far, middle)]
        }
        if stones >= 8 {
            points += [point(middle, edge), point(middle, far)]
        }
        if stones % 2 == 1 {
            points.append(point(middle, middle))
        }
        return Array(points.prefix(max(0, min(stones, points.count))))
    }

    /// A number as the shortest text that reads back the same: 7.5, 0.5, 7.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return "\(value)"
    }
}
