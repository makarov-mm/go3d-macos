/// A fast generator for the playouts (xorshift64*).
struct FastRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed != 0 ? seed : 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// From 0 to n - 1.
    mutating func below(_ n: Int) -> Int {
        Int(truncatingIfNeeded: ((next() >> 32) &* UInt64(n)) >> 32)
    }
}
