import Foundation

// Small vector and matrix types on the standard library's SIMD vectors. Matrices are column-major, like Metal's, and
// multiply column vectors; the projections give Metal's depth range of 0 to 1.

typealias Vec2 = SIMD2<Float>
typealias Vec3 = SIMD3<Float>
typealias Vec4 = SIMD4<Float>

extension SIMD3 where Scalar == Float {
    var length: Float { (self * self).sum().squareRoot() }

    /// Of unit length; straight up when the vector is too short to have a direction.
    var normalized: Vec3 {
        let length = length
        return length > 1e-20 ? self / length : Vec3(0, 1, 0)
    }

    func dot(_ other: Vec3) -> Float { (self * other).sum() }

    func cross(_ other: Vec3) -> Vec3 {
        Vec3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    /// With a fourth component, as a point (1) or a direction (0).
    func extended(_ w: Float) -> Vec4 { Vec4(x, y, z, w) }
}

extension SIMD4 where Scalar == Float {
    var xyz: Vec3 { Vec3(x, y, z) }
}

func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
func lerp(_ a: Vec3, _ b: Vec3, _ t: Float) -> Vec3 { a + (b - a) * t }
func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T { min(max(value, lower), upper) }

/// A 4×4 matrix of four columns, laid out as Metal's `float4x4`.
struct Mat4: Sendable {
    var columns: (Vec4, Vec4, Vec4, Vec4)

    init(_ c0: Vec4, _ c1: Vec4, _ c2: Vec4, _ c3: Vec4) {
        columns = (c0, c1, c2, c3)
    }

    static let identity = Mat4(Vec4(1, 0, 0, 0), Vec4(0, 1, 0, 0), Vec4(0, 0, 1, 0), Vec4(0, 0, 0, 1))

    /// The element in a row and a column.
    subscript(row: Int, column: Int) -> Float {
        get { self[column][row] }
        set { self[column][row] = newValue }
    }

    subscript(column: Int) -> Vec4 {
        get {
            switch column {
            case 0: columns.0
            case 1: columns.1
            case 2: columns.2
            default: columns.3
            }
        }
        set {
            switch column {
            case 0: columns.0 = newValue
            case 1: columns.1 = newValue
            case 2: columns.2 = newValue
            default: columns.3 = newValue
            }
        }
    }

    static func translation(_ t: Vec3) -> Mat4 {
        var result = identity
        result.columns.3 = Vec4(t.x, t.y, t.z, 1)
        return result
    }

    static func rotationX(_ angle: Float) -> Mat4 {
        let c = cos(angle), s = sin(angle)
        var result = identity
        result[1, 1] = c
        result[1, 2] = -s
        result[2, 1] = s
        result[2, 2] = c
        return result
    }

    static func rotationY(_ angle: Float) -> Mat4 {
        let c = cos(angle), s = sin(angle)
        var result = identity
        result[0, 0] = c
        result[0, 2] = s
        result[2, 0] = -s
        result[2, 2] = c
        return result
    }

    /// About an axis of unit length, counterclockwise looking down it.
    static func rotation(axis: Vec3, angle: Float) -> Mat4 {
        let c = cos(angle), s = sin(angle), t = 1 - c
        var result = identity
        result[0, 0] = c + t * axis.x * axis.x
        result[0, 1] = t * axis.x * axis.y - s * axis.z
        result[0, 2] = t * axis.x * axis.z + s * axis.y
        result[1, 0] = t * axis.y * axis.x + s * axis.z
        result[1, 1] = c + t * axis.y * axis.y
        result[1, 2] = t * axis.y * axis.z - s * axis.x
        result[2, 0] = t * axis.z * axis.x - s * axis.y
        result[2, 1] = t * axis.z * axis.y + s * axis.x
        result[2, 2] = c + t * axis.z * axis.z
        return result
    }

    static func lookAt(eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
        let forward = (target - eye).normalized
        let right = forward.cross(up).normalized
        let trueUp = right.cross(forward)
        var result = identity
        result[0, 0] = right.x
        result[0, 1] = right.y
        result[0, 2] = right.z
        result[1, 0] = trueUp.x
        result[1, 1] = trueUp.y
        result[1, 2] = trueUp.z
        result[2, 0] = -forward.x
        result[2, 1] = -forward.y
        result[2, 2] = -forward.z
        result[0, 3] = -right.dot(eye)
        result[1, 3] = -trueUp.dot(eye)
        result[2, 3] = forward.dot(eye)
        return result
    }

    /// Looking down -z; depth from 0 at the near plane to 1 at the far plane.
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> Mat4 {
        let f = 1 / tan(fovY / 2)
        var result = Mat4(.zero, .zero, .zero, .zero)
        result[0, 0] = f / aspect
        result[1, 1] = f
        result[2, 2] = far / (near - far)
        result[2, 3] = far * near / (near - far)
        result[3, 2] = -1
        return result
    }

    /// Depth from 0 at the near plane to 1 at the far plane.
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> Mat4 {
        var result = identity
        result[0, 0] = 2 / (right - left)
        result[1, 1] = 2 / (top - bottom)
        result[2, 2] = -1 / (far - near)
        result[0, 3] = -(right + left) / (right - left)
        result[1, 3] = -(top + bottom) / (top - bottom)
        result[2, 3] = -near / (far - near)
        return result
    }

    static func * (a: Mat4, b: Mat4) -> Mat4 {
        Mat4(a * b.columns.0, a * b.columns.1, a * b.columns.2, a * b.columns.3)
    }

    static func * (m: Mat4, v: Vec4) -> Vec4 {
        m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z + m.columns.3 * v.w
    }

    func transformPoint(_ p: Vec3) -> Vec3 {
        let v = self * p.extended(1)
        return v.xyz / v.w
    }

    /// The upper left 3×3 part applied to a direction.
    func transformDirection(_ d: Vec3) -> Vec3 { (self * d.extended(0)).xyz }

    var inverse: Mat4 {
        // Cofactors, after the expansion in Mesa's gluInvertMatrix, on the elements in column-major order.
        let a = (0..<16).map { self[$0 / 4][$0 % 4] }
        var inv = [Float](repeating: 0, count: 16)
        inv[0] = a[5] * a[10] * a[15] - a[5] * a[11] * a[14] - a[9] * a[6] * a[15] + a[9] * a[7] * a[14] + a[13] * a[6] * a[11] - a[13] * a[7] * a[10]
        inv[4] = -a[4] * a[10] * a[15] + a[4] * a[11] * a[14] + a[8] * a[6] * a[15] - a[8] * a[7] * a[14] - a[12] * a[6] * a[11] + a[12] * a[7] * a[10]
        inv[8] = a[4] * a[9] * a[15] - a[4] * a[11] * a[13] - a[8] * a[5] * a[15] + a[8] * a[7] * a[13] + a[12] * a[5] * a[11] - a[12] * a[7] * a[9]
        inv[12] = -a[4] * a[9] * a[14] + a[4] * a[10] * a[13] + a[8] * a[5] * a[14] - a[8] * a[6] * a[13] - a[12] * a[5] * a[10] + a[12] * a[6] * a[9]
        inv[1] = -a[1] * a[10] * a[15] + a[1] * a[11] * a[14] + a[9] * a[2] * a[15] - a[9] * a[3] * a[14] - a[13] * a[2] * a[11] + a[13] * a[3] * a[10]
        inv[5] = a[0] * a[10] * a[15] - a[0] * a[11] * a[14] - a[8] * a[2] * a[15] + a[8] * a[3] * a[14] + a[12] * a[2] * a[11] - a[12] * a[3] * a[10]
        inv[9] = -a[0] * a[9] * a[15] + a[0] * a[11] * a[13] + a[8] * a[1] * a[15] - a[8] * a[3] * a[13] - a[12] * a[1] * a[11] + a[12] * a[3] * a[9]
        inv[13] = a[0] * a[9] * a[14] - a[0] * a[10] * a[13] - a[8] * a[1] * a[14] + a[8] * a[2] * a[13] + a[12] * a[1] * a[10] - a[12] * a[2] * a[9]
        inv[2] = a[1] * a[6] * a[15] - a[1] * a[7] * a[14] - a[5] * a[2] * a[15] + a[5] * a[3] * a[14] + a[13] * a[2] * a[7] - a[13] * a[3] * a[6]
        inv[6] = -a[0] * a[6] * a[15] + a[0] * a[7] * a[14] + a[4] * a[2] * a[15] - a[4] * a[3] * a[14] - a[12] * a[2] * a[7] + a[12] * a[3] * a[6]
        inv[10] = a[0] * a[5] * a[15] - a[0] * a[7] * a[13] - a[4] * a[1] * a[15] + a[4] * a[3] * a[13] + a[12] * a[1] * a[7] - a[12] * a[3] * a[5]
        inv[14] = -a[0] * a[5] * a[14] + a[0] * a[6] * a[13] + a[4] * a[1] * a[14] - a[4] * a[2] * a[13] - a[12] * a[1] * a[6] + a[12] * a[2] * a[5]
        inv[3] = -a[1] * a[6] * a[11] + a[1] * a[7] * a[10] + a[5] * a[2] * a[11] - a[5] * a[3] * a[10] - a[9] * a[2] * a[7] + a[9] * a[3] * a[6]
        inv[7] = a[0] * a[6] * a[11] - a[0] * a[7] * a[10] - a[4] * a[2] * a[11] + a[4] * a[3] * a[10] + a[8] * a[2] * a[7] - a[8] * a[3] * a[6]
        inv[11] = -a[0] * a[5] * a[11] + a[0] * a[7] * a[9] + a[4] * a[1] * a[11] - a[4] * a[3] * a[9] - a[8] * a[1] * a[7] + a[8] * a[3] * a[5]
        inv[15] = a[0] * a[5] * a[10] - a[0] * a[6] * a[9] - a[4] * a[1] * a[10] + a[4] * a[2] * a[9] + a[8] * a[1] * a[6] - a[8] * a[2] * a[5]

        let determinant = a[0] * inv[0] + a[1] * inv[4] + a[2] * inv[8] + a[3] * inv[12]
        guard determinant != 0 else { return .identity }
        var result = Mat4.identity
        for i in 0..<16 {
            result[i / 4][i % 4] = inv[i] / determinant
        }
        return result
    }
}

