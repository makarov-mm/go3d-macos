import Foundation

/// A vertex of the board, the table and the bowls, laid out as `SurfaceVertex` in the shaders.
struct SurfaceVertex {
    var position: Vec3
    var normal: Vec3
    var uv: Vec2
}

struct SurfaceMesh {
    var vertices: [SurfaceVertex] = []
    var indices: [UInt32] = []

    /// Adds a quad, wound counterclockwise as seen from the side its normal faces.
    mutating func addQuad(_ a: SurfaceVertex, _ b: SurfaceVertex, _ c: SurfaceVertex, _ d: SurfaceVertex) {
        let base = UInt32(vertices.count)
        vertices += [a, b, c, d]
        let facing = (b.position - a.position).cross(c.position - a.position)
        let normal = a.normal + b.normal + c.normal + d.normal
        if facing.dot(normal) >= 0 {
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        } else {
            indices += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
    }
}

/// Where everything stands for a size of board. The lines of the board are one unit apart and its surface is the
/// plane y = 0; Black looks from +z, where row 1 is.
struct BoardLayout: Sendable {
    var size = 19
    /// From the middle to the outer lines.
    var half: Float = 9
    /// To the edge of the board.
    var boardHalf: Float = 10
    var thickness: Float = 0.9
    var bowlRadius: Float = 2.5
    var bowlHeight: Float = 2
    /// Black's and White's, on the table.
    var bowls = [Vec3](repeating: .zero, count: 2)
    /// Turned over beside them, for the stones taken.
    var lids = [Vec3](repeating: .zero, count: 2)

    init(size: Int) {
        self.size = size
        half = Float(size - 1) / 2
        boardHalf = half + 0.95 // room for the coordinates round the lines
        thickness = 0.9
        bowlRadius = max(2.2, 0.28 * boardHalf)
        bowlHeight = bowlRadius * 0.78
        // Each player's bowl on the right, toward the player; the lid beside it.
        let x = boardHalf + 0.8 + bowlRadius
        let z = min(boardHalf * 0.45, boardHalf - bowlRadius)
        let lidZ = z - 2 * bowlRadius - 0.4
        let y = -thickness
        bowls = [Vec3(x, y, z), Vec3(-x, y, -z)]
        lids = [Vec3(x, y, lidZ), Vec3(-x, y, -lidZ)]
    }

    var tableHeight: Float { -thickness }
    /// How far the scene reaches from the middle, for the camera.
    var extent: Float { boardHalf + bowlRadius * 1.2 }

    func center(of point: GoPoint) -> Vec3 {
        Vec3(Float(Go.x(point)) - half, 0, Float(Go.y(point)) - half)
    }

    /// The point nearest a point of the surface, or `Go.pass` off the board.
    func point(near position: Vec3) -> GoPoint {
        let x = Int((position.x + half).rounded()), y = Int((position.z + half).rounded())
        return x >= 0 && y >= 0 && x < size && y < size ? Go.point(x, y) : Go.pass
    }

    /// The height of the floor of a lid of this radius, where the stones taken lie.
    static func lidFloor(radius: Float) -> Float { radius * 0.07 }
    /// The height of the top of the heap of stones in a bowl.
    static func heapHeight(height: Float) -> Float { height * 0.78 }
}

/// Meshes of the board, the table, and the bowls with their lids.
enum BoardGeometry {
    /// The rounded upper edge of the board.
    private static let bevel: Float = 0.06

    static func boardTop(_ layout: BoardLayout) -> SurfaceMesh {
        var mesh = SurfaceMesh()
        let e = layout.boardHalf - bevel
        let up = Vec3(0, 1, 0)
        mesh.addQuad(SurfaceVertex(position: Vec3(-e, 0, e), normal: up, uv: Vec2(-e, e)),
                     SurfaceVertex(position: Vec3(e, 0, e), normal: up, uv: Vec2(e, e)),
                     SurfaceVertex(position: Vec3(e, 0, -e), normal: up, uv: Vec2(e, -e)),
                     SurfaceVertex(position: Vec3(-e, 0, -e), normal: up, uv: Vec2(-e, -e)))
        return mesh
    }

    /// The rounded edge and the sides, swept round the top with mitred corners.
    static func boardSides(_ layout: BoardLayout) -> SurfaceMesh {
        struct SidePoint {
            var out, y: Float   // outward from the edge of the flat top, and height
            var nOut, nY: Float // normal
        }
        var profile: [SidePoint] = []
        for i in 0...4 {
            let angle = Float.pi / 2 * Float(i) / 4
            profile.append(SidePoint(out: bevel * sin(angle), y: -bevel * (1 - cos(angle)), nOut: sin(angle), nY: cos(angle)))
        }
        profile.append(SidePoint(out: bevel, y: -layout.thickness, nOut: 1, nY: 0))

        let outward = [Vec3(0, 0, 1), Vec3(1, 0, 0), Vec3(0, 0, -1), Vec3(-1, 0, 0)]
        let inner = layout.boardHalf - bevel
        var mesh = SurfaceMesh()
        for o in outward {
            let along = Vec3(-o.z, 0, o.x)
            for i in 0..<profile.count - 1 {
                let p = profile[i], q = profile[i + 1]
                let pExtent = inner + p.out, qExtent = inner + q.out
                func vertex(_ point: SidePoint, _ extent: Float, _ s: Float) -> SurfaceVertex {
                    SurfaceVertex(position: o * extent + along * s + Vec3(0, point.y, 0),
                                  normal: (o * point.nOut + Vec3(0, point.nY, 0)).normalized, uv: Vec2(s, point.y))
                }
                mesh.addQuad(vertex(p, pExtent, -pExtent), vertex(p, pExtent, pExtent), vertex(q, qExtent, qExtent), vertex(q, qExtent, -qExtent))
            }
        }
        return mesh
    }

    static func table(radius: Float, height: Float) -> SurfaceMesh {
        var mesh = SurfaceMesh()
        let up = Vec3(0, 1, 0)
        let segments = 96
        mesh.vertices.append(SurfaceVertex(position: Vec3(0, height, 0), normal: up, uv: Vec2(0.5, 0.5)))
        for i in 0..<segments {
            let angle = 2 * Float.pi * Float(i) / Float(segments)
            let x = cos(angle) * radius, z = sin(angle) * radius
            mesh.vertices.append(SurfaceVertex(position: Vec3(x, height, z), normal: up, uv: Vec2(x / radius * 0.5 + 0.5, z / radius * 0.5 + 0.5)))
        }
        for i in 0..<UInt32(segments) {
            // Counterclockwise from above: from +x toward -z.
            let a = 1 + i, b = 1 + (i + 1) % UInt32(segments)
            mesh.indices += [0, b, a]
        }
        return mesh
    }

    /// A bowl, standing on y = 0 round the y axis; uv runs along the outline and round.
    static func bowl(radius r: Float, height h: Float) -> SurfaceMesh {
        var profile: [Vec2] = [Vec2(0, 0), Vec2(0.58 * r, 0), Vec2(0.62 * r, 0.03 * h)]
        // The belly: widest a little below the middle, drawing in to the mouth.
        for i in 1...24 {
            let t = 0.03 + 0.97 * Float(i) / 24
            let below = 0.62 + 0.38 * sin(.pi / 2 * t / 0.42)
            let above = 1 - 0.17 * ((t - 0.42) / 0.58) * ((t - 0.42) / 0.58)
            profile.append(Vec2((t < 0.42 ? below : above) * r, t * h))
        }
        // The lip, and the inside down to the heap of stones.
        let heap = BoardLayout.heapHeight(height: h) - 0.05
        profile += [Vec2(0.815 * r, 1.012 * h), Vec2(0.79 * r, 1.012 * h), Vec2(0.77 * r, h), Vec2(0.74 * r, 0.9 * h),
                    Vec2(0.72 * r, heap), Vec2(0.4 * r, heap), Vec2(0, heap)]
        return lathe(profile, segments: 72)
    }

    /// A lid, turned over, standing on y = 0.
    static func lid(radius r: Float) -> SurfaceMesh {
        let floor = BoardLayout.lidFloor(radius: r)
        let profile = [Vec2(0, 0), Vec2(0.84 * r, 0), Vec2(0.9 * r, 0.03 * r), Vec2(0.96 * r, 0.1 * r),
                       Vec2(r, 0.19 * r), Vec2(0.99 * r, 0.22 * r), Vec2(0.96 * r, 0.225 * r), Vec2(0.935 * r, 0.2 * r),
                       Vec2(0.9 * r, 0.11 * r), Vec2(0.84 * r, floor), Vec2(0.42 * r, floor), Vec2(0, floor)]
        return lathe(profile, segments: 72)
    }

    /// An outline of (radius, height) points turned round the y axis. Normals come from the neighbouring points, the
    /// outline running with the outside on its right; uv is the distance along the outline and the turn.
    private static func lathe(_ profile: [Vec2], segments: Int) -> SurfaceMesh {
        var mesh = SurfaceMesh()
        let count = profile.count
        var along = [Float](repeating: 0, count: count)
        for i in 1..<count {
            along[i] = along[i - 1] + (profile[i] - profile[i - 1]).length
        }
        for i in 0..<count {
            let before = profile[max(i - 1, 0)], after = profile[min(i + 1, count - 1)]
            let tangent = after - before
            let length = max(tangent.length, 1e-6)
            let nr = tangent.y / length, ny = -tangent.x / length
            let point = profile[i]
            for j in 0...segments {
                let t = Float(j) / Float(segments)
                let c = cos(2 * .pi * t), s = sin(2 * .pi * t)
                mesh.vertices.append(SurfaceVertex(position: Vec3(point.x * c, point.y, point.x * s),
                                                   normal: Vec3(nr * c, ny, nr * s).normalized, uv: Vec2(along[i], t)))
            }
        }
        func index(_ i: Int, _ j: Int) -> UInt32 { UInt32(i * (segments + 1) + j) }
        for i in 0..<count - 1 {
            for j in 0..<segments {
                if profile[i].x > 0 {
                    mesh.indices += [index(i, j), index(i + 1, j + 1), index(i, j + 1)]
                }
                if profile[i + 1].x > 0 {
                    mesh.indices += [index(i, j), index(i + 1, j), index(i + 1, j + 1)]
                }
            }
        }
        return mesh
    }
}

extension SIMD2 where Scalar == Float {
    var length: Float { (self * self).sum().squareRoot() }
}
