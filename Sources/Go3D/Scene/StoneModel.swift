import Foundation

/// A vertex of a stone, laid out as `StoneVertex` in the shaders.
struct StoneVertex {
    var position: Vec3
    var normal: Vec3
}

struct StoneMesh {
    var vertices: [StoneVertex] = []
    var indices: [UInt32] = []
}

/// The stone: a lens, both faces gently domed and meeting in a rounded edge, as Japanese stones are cut. Its middle is
/// the origin; it lies with its axis along y. The lines of the board are one unit apart.
enum StoneModel {
    static let radius: Float = 0.475
    static let halfHeight: Float = 0.19

    /// For the scene, and a simpler one for the shadows and the reflections.
    static func build() -> (detailed: StoneMesh, simple: StoneMesh) {
        (build(rings: 14, segments: 48), build(rings: 5, segments: 20))
    }

    /// The height of the face at a distance from the axis: flat in the middle, falling steeply at the edge.
    private static func faceHeight(_ r: Float) -> Float {
        let t = min(r / radius, 1)
        return halfHeight * pow(1 - t * t, 0.75)
    }

    /// The outline from the middle of the lower face round the edge to the middle of the upper face, its points
    /// crowded at the edge where it turns fastest, turned round the axis.
    private static func build(rings: Int, segments: Int) -> StoneMesh {
        struct ProfilePoint {
            var r, y: Float
            var normal: Vec2
        }
        // A point of a face, sign 1 for the upper and -1 for the lower, with its outward normal from the slope.
        func face(_ r: Float, _ sign: Float) -> ProfilePoint {
            let d: Float = 0.0005
            let a = max(r - d, 0), b = min(r + d, radius)
            let slope = (faceHeight(b) - faceHeight(a)) / (b - a)
            let length = (1 + slope * slope).squareRoot()
            return ProfilePoint(r: r, y: sign * faceHeight(r), normal: Vec2(-slope / length, sign / length))
        }
        var profile: [ProfilePoint] = []
        for i in 0..<rings {
            profile.append(face(radius * sin(.pi / 2 * Float(i) / Float(rings)), -1))
        }
        profile.append(ProfilePoint(r: radius, y: 0, normal: Vec2(1, 0)))
        for i in stride(from: rings - 1, through: 0, by: -1) {
            profile.append(face(radius * sin(.pi / 2 * Float(i) / Float(rings)), 1))
        }

        var mesh = StoneMesh()
        for point in profile {
            for j in 0...segments {
                let angle = 2 * Float.pi * Float(j) / Float(segments)
                let c = cos(angle), s = sin(angle)
                mesh.vertices.append(StoneVertex(position: Vec3(point.r * c, point.y, point.r * s),
                                                 normal: Vec3(point.normal.x * c, point.normal.y, point.normal.x * s).normalized))
            }
        }
        func index(_ i: Int, _ j: Int) -> UInt32 { UInt32(i * (segments + 1) + j) }
        for i in 0..<profile.count - 1 {
            for j in 0..<segments {
                // Next to the axis a quad narrows to a triangle.
                if profile[i].r > 0 {
                    mesh.indices += [index(i, j), index(i + 1, j + 1), index(i, j + 1)]
                }
                if profile[i + 1].r > 0 {
                    mesh.indices += [index(i, j), index(i + 1, j), index(i + 1, j + 1)]
                }
            }
        }
        return mesh
    }
}
