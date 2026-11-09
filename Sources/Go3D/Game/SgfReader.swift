/// Reads the nodes of an SGF game's main line: at each fork, the first variation. The text is read as bytes, so
/// that names and comments in any encoding pass through untouched.
struct SgfReader {
    struct Property {
        var name: String
        var values: [String]
    }

    struct Node {
        var properties: [Property] = []

        func values(_ name: String) -> [String] { properties.first { $0.name == name }?.values ?? [] }
        /// The first value of a property, when it has one.
        func value(_ name: String) -> String? { values(name).first }
    }

    private let text: [UInt8]
    private var at = 0

    init(_ text: [UInt8]) {
        self.text = text
    }

    mutating func mainLine() throws(GameRecordError) -> [Node] {
        skipSpace()
        guard accept(UInt8(ascii: "(")) else { throw GameRecordError("not an SGF game") }
        var nodes: [Node] = []
        try sequence(&nodes)
        return nodes
    }

    private mutating func sequence(_ nodes: inout [Node]) throws(GameRecordError) {
        while true {
            skipSpace()
            guard at < text.count else { return } // a game cut short is read as far as it goes
            switch text[at] {
            case UInt8(ascii: ";"):
                at += 1
                nodes.append(readNode())
            case UInt8(ascii: "("):
                // The first variation is followed; the others are skipped.
                at += 1
                try sequence(&nodes)
                skipVariations()
                return
            case UInt8(ascii: ")"):
                at += 1
                return
            case let other:
                throw GameRecordError("unexpected '\(Character(Unicode.Scalar(other)))'")
            }
        }
    }

    private mutating func readNode() -> Node {
        var node = Node()
        while true {
            skipSpace()
            // A property's name is its capital letters; lowercase letters in it are old style and dropped.
            var name: [UInt8] = []
            while at < text.count && isLetter(text[at]) {
                if text[at] >= UInt8(ascii: "A") && text[at] <= UInt8(ascii: "Z") {
                    name.append(text[at])
                }
                at += 1
            }
            if name.isEmpty {
                return node
            }
            var property = Property(name: String(decoding: name, as: UTF8.self), values: [])
            skipSpace()
            while at < text.count && text[at] == UInt8(ascii: "[") {
                at += 1
                var value: [UInt8] = []
                while at < text.count && text[at] != UInt8(ascii: "]") {
                    if text[at] == UInt8(ascii: "\\") && at + 1 < text.count {
                        at += 1
                    }
                    value.append(text[at])
                    at += 1
                }
                at += 1
                property.values.append(String(decoding: value, as: UTF8.self))
                skipSpace()
            }
            node.properties.append(property)
        }
    }

    /// After the first variation, the rest up to the end of the enclosing sequence.
    private mutating func skipVariations() {
        var depth = 0
        var inValue = false
        while at < text.count {
            let c = text[at]
            at += 1
            if inValue {
                if c == UInt8(ascii: "\\") {
                    at += 1
                } else if c == UInt8(ascii: "]") {
                    inValue = false
                }
            } else if c == UInt8(ascii: "[") {
                inValue = true
            } else if c == UInt8(ascii: "(") {
                depth += 1
            } else if c == UInt8(ascii: ")") {
                if depth == 0 {
                    return
                }
                depth -= 1
            }
        }
    }

    private mutating func skipSpace() {
        while at < text.count && [9, 10, 13, 32].contains(text[at]) {
            at += 1
        }
    }

    private mutating func accept(_ c: UInt8) -> Bool {
        guard at < text.count && text[at] == c else { return false }
        at += 1
        return true
    }

    private func isLetter(_ c: UInt8) -> Bool {
        (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z")) || (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
    }

    // MARK: Points

    /// "dd" for a point; empty for a pass.
    static func point(_ point: GoPoint) -> String {
        guard point != Go.pass else { return "" }
        let a = UInt8(ascii: "a")
        return String(decoding: [a + UInt8(Go.x(point)), a + UInt8(Go.y(point))], as: UTF8.self)
    }

    /// "dd", or a rectangle "aa:cc" in a list of setup stones.
    static func points(_ value: String, size: Int) -> [GoPoint] {
        func one(_ text: Substring) -> (x: Int, y: Int)? {
            let bytes = Array(text.utf8)
            guard bytes.count == 2 else { return nil }
            let x = Int(bytes[0]) - Int(UInt8(ascii: "a")), y = Int(bytes[1]) - Int(UInt8(ascii: "a"))
            guard x >= 0, y >= 0, x < size, y < size else { return nil }
            return (x, y)
        }
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = one(parts[0]) else { return [] }
        let last = parts.count > 1 ? one(parts[1]) ?? first : first
        var points: [GoPoint] = []
        for y in min(first.y, last.y)...max(first.y, last.y) {
            for x in min(first.x, last.x)...max(first.x, last.x) {
                points.append(Go.point(x, y))
            }
        }
        return points
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        for c in text {
            if c == "]" || c == "\\" {
                escaped.append("\\")
            }
            escaped.append(c)
        }
        return escaped
    }

    /// Where a run of bytes first occurs.
    static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where haystack[start..<start + needle.count].elementsEqual(needle) {
            return start
        }
        return nil
    }
}
