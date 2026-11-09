import Foundation

/// A color of the interface, as the screen shows it, with straight alpha.
struct UiColor: Sendable {
    var r: UInt8 = 255, g: UInt8 = 255, b: UInt8 = 255, a: UInt8 = 255

    init(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        self.r = UInt8(clamping: r)
        self.g = UInt8(clamping: g)
        self.b = UInt8(clamping: b)
        self.a = UInt8(clamping: a)
    }

    /// A linear color of the scene, as it shows on the screen.
    init(linear color: Vec3, alpha: Float = 1) {
        func encode(_ c: Float) -> Int { Int((pow(clamp(c, 0, 1), 1 / 2.2) * 255).rounded()) }
        self.init(encode(color.x), encode(color.y), encode(color.z), Int((clamp(alpha, 0, 1) * 255).rounded()))
    }

    func faded(_ opacity: Float) -> UiColor {
        var color = self
        color.a = UInt8(clamp(Float(a) * opacity, 0, 255))
        return color
    }

    func mixed(with other: UiColor, _ t: Float) -> UiColor {
        let t = clamp(t, 0, 1)
        func mix(_ x: UInt8, _ y: UInt8) -> Int { Int(lerp(Float(x), Float(y), t).rounded()) }
        return UiColor(mix(r, other.r), mix(g, other.g), mix(b, other.b), mix(a, other.a))
    }

    var vector: Vec4 { Vec4(Float(r), Float(g), Float(b), Float(a)) / 255 }
}

/// A rectangle of the window, in pixels from the top left.
struct UiRect: Sendable {
    var x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0

    var right: Float { x + width }
    var bottom: Float { y + height }

    func contains(_ px: Float, _ py: Float) -> Bool { px >= x && px < x + width && py >= y && py < y + height }
    func inset(_ d: Float) -> UiRect { UiRect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
}
