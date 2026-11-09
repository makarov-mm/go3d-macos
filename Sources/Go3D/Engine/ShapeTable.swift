/// Local 3×3 shapes in which the middle point is a good move, for the playouts and the priors of the tree.
enum ShapeTable {
    /// The eight points round a point, in the order of their bits in a shape's code.
    @inline(__always)
    static func around(_ point: GoPoint, _ slot: Int) -> GoPoint {
        switch slot {
        case 0: point - 22
        case 1: point - 21
        case 2: point - 20
        case 3: point - 1
        case 4: point + 1
        case 5: point + 20
        case 6: point + 21
        default: point + 22
        }
    }

    /// The shapes (from MoGo and Pachi): X and O are the two colors either way round, unless a tenth character says X
    /// is to play; x is anything but X, o anything but O, # off the board, ? anything.
    private static let shapes = [
        "XOX...???",  // hane, enclosing
        "XO....?.?",  // hane, not cutting
        "XO?X..x.?",  // hane, bending round
        "XOO...?.?X", // thin hane
        ".O.X.....",  // diagonal attachment
        "XO?O.o?o?",  // cut, unprotected
        "XO?O.X???",  // cut, peeped
        "?X?O.Oooo",  // pushing through
        "OX?o.O???",  // cutting a knight's move
        "X.?O.?##?",  // edge: chasing
        "OX?X.O###",  // edge: blocking a cut
        "?X?x.O###",  // edge: blocking a connection
        "?XOx.x###",  // edge: dropping back
        "?OXo.O?##X", // edge: throwing in
        "?OXX.O###X", // edge: cutting
    ]

    /// For each arrangement of the eight points round an empty point (two bits each, as `Cell.code`), whether a shape
    /// matches with Black to play (bit 0) and with White to play (bit 1).
    static let table: [UInt8] = {
        var result = [UInt8](repeating: 0, count: 65536)
        let center = Go.point(1, 1)
        for shape in shapes {
            let characters = Array(shape.utf8)
            let xToPlay = characters.count > 9 && characters[9] == UInt8(ascii: "X")
            for symmetry in 0..<8 {
                // The shape's character at each of the eight points, turned and mirrored.
                var wanted = [UInt8](repeating: 0, count: 8)
                for row in 0..<3 {
                    for column in 0..<3 {
                        var dx = column - 1, dy = row - 1
                        if dx == 0 && dy == 0 {
                            continue
                        }
                        if symmetry & 1 != 0 {
                            dx = -dx
                        }
                        if symmetry & 2 != 0 {
                            dy = -dy
                        }
                        if symmetry & 4 != 0 {
                            swap(&dx, &dy)
                        }
                        let slot = (0..<8).first { around(center, $0) == center + dy * Go.stride + dx }!
                        wanted[slot] = characters[row * 3 + column]
                    }
                }
                for x in [Cell.black.code, Cell.white.code] {
                    let o = x == Cell.black.code ? Cell.white.code : Cell.black.code
                    let players: UInt8 = xToPlay ? (x == Cell.black.code ? 1 : 2) : 3
                    // The cells each point allows, then every code made of them.
                    let allowed = wanted.map { c in
                        (0..<4).filter { cell in
                            switch c {
                            case UInt8(ascii: "X"): cell == x
                            case UInt8(ascii: "O"): cell == o
                            case UInt8(ascii: "."): cell == Cell.empty.code
                            case UInt8(ascii: "#"): cell == Cell.border.code
                            case UInt8(ascii: "x"): cell != x
                            case UInt8(ascii: "o"): cell != o
                            default: true
                            }
                        }
                    }
                    var codes = [0]
                    for slot in 0..<8 {
                        codes = codes.flatMap { code in allowed[slot].map { code | $0 << (2 * slot) } }
                    }
                    for code in codes {
                        result[code] |= players
                    }
                }
            }
        }
        return result
    }()

    /// A shape matches round an empty point for the side to play.
    @inline(__always)
    static func matches(_ table: [UInt8], _ board: Board, _ point: GoPoint, _ toPlay: StoneColor) -> Bool {
        var code = 0
        for slot in 0..<8 {
            code |= board.code(at: around(point, slot)) << (2 * slot)
        }
        return table[code] & (toPlay == .black ? 1 : 2) != 0
    }
}
