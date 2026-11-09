import Foundation

/// A camera circling the board. Its moves are eased: dragging, zooming and turning set where it heads.
struct OrbitCamera {
    private static let defaultPitch: Float = 0.96
    private static let minPitch: Float = 0.22
    private static let maxPitch: Float = 1.53
    private static let fieldOfView: Float = 0.6
    /// Of the space for the board, below which the view widens.
    private static let minAspect: Float = 1.45
    private static let target = Vec3(0, 0.15, 0)

    private var reach: Float = 13
    private var yaw: Float = 0, pitch = defaultPitch, distance: Float = 32, shift: Float = 0, space: Float = 1
    private var targetYaw: Float = 0, targetPitch = defaultPitch, targetDistance: Float = 32, targetShift: Float = 0, targetSpace: Float = 1
    private var topView = false
    private var savedPitch = defaultPitch

    private var defaultDistance: Float { 2.6 * reach }

    /// How far the scene reaches from the middle: the distances scale with it, so that a board of another size is
    /// seen from as far in proportion.
    mutating func setReach(_ newReach: Float) {
        guard abs(newReach - reach) >= 1e-4 else { return }
        let ratio = newReach / reach
        reach = newReach
        targetDistance *= ratio
        distance *= ratio
    }

    /// Black looks from +z, where row 1 is near; White from the other side.
    mutating func face(_ side: StoneColor) {
        targetYaw = Self.unwrap(side == .black ? 0 : .pi, near: targetYaw)
    }

    mutating func flip() {
        targetYaw += .pi
    }

    mutating func toggleTopView() {
        topView.toggle()
        if topView {
            savedPitch = targetPitch
            targetPitch = Self.maxPitch
        } else {
            targetPitch = savedPitch
        }
    }

    mutating func reset(_ side: StoneColor) {
        face(side)
        targetPitch = Self.defaultPitch
        targetDistance = defaultDistance
        topView = false
    }

    mutating func rotate(yaw yawRadians: Float, pitch pitchRadians: Float) {
        targetYaw += yawRadians
        targetPitch = clamp(targetPitch + pitchRadians, Self.minPitch, Self.maxPitch)
        topView = false
    }

    mutating func zoom(_ steps: Float) {
        targetDistance = clamp(targetDistance * pow(0.9, steps), 1.1 * reach, 4.3 * reach)
    }

    /// The share of the window's width left for the board beside the panel: the view centers on it, and widens when
    /// it is narrow, so the board and the bowls beside it stay in sight.
    mutating func setSpace(_ share: Float) {
        targetShift = (share - 1) / 2
        targetSpace = share
    }

    mutating func update(_ seconds: Float) {
        let ease = 1 - exp(-seconds * 9)
        yaw += (targetYaw - yaw) * ease
        pitch += (targetPitch - pitch) * ease
        distance += (targetDistance - distance) * ease
        shift += (targetShift - shift) * ease
        space += (targetSpace - space) * ease
    }

    var isMoving: Bool {
        abs(targetYaw - yaw) > 1e-4 || abs(targetPitch - pitch) > 1e-4 || abs(targetDistance - distance) > 1e-3 ||
            abs(targetShift - shift) > 1e-4 || abs(targetSpace - space) > 1e-4
    }

    var eye: Vec3 {
        let horizontal = cos(pitch)
        return Self.target + Vec3(sin(yaw) * horizontal, sin(pitch), cos(yaw) * horizontal) * distance
    }

    var view: Mat4 {
        // Looking straight down, "up" on the screen points away from the player.
        let up = Vec3(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch)).normalized
        return Mat4.lookAt(eye: eye, target: Self.target, up: up)
    }

    func projection(aspect: Float) -> Mat4 {
        let widen = max(1, Self.minAspect / (aspect * space))
        var projection = Mat4.perspective(fovY: 2 * atan(tan(Self.fieldOfView / 2) * widen), aspect: aspect,
                                          near: 0.02 * reach, far: 12 * reach)
        projection[0, 2] = -2 * shift // a shift in normalized coordinates, which span 2
        return projection
    }

    /// The ray through a point of the window, in pixels from the top left.
    func ray(x: Float, y: Float, width: Float, height: Float) -> (origin: Vec3, direction: Vec3) {
        let inverse = (projection(aspect: width / max(height, 1)) * view).inverse
        let nx = x / width * 2 - 1, ny = 1 - y / height * 2
        let nearPoint = inverse.transformPoint(Vec3(nx, ny, 0))
        let farPoint = inverse.transformPoint(Vec3(nx, ny, 1))
        return (nearPoint, (farPoint - nearPoint).normalized)
    }

    /// The angle nearest to `current` that points the same way as `angle`.
    private static func unwrap(_ angle: Float, near current: Float) -> Float {
        var angle = angle
        while angle - current > .pi {
            angle -= 2 * .pi
        }
        while angle - current < -.pi {
            angle += 2 * .pi
        }
        return angle
    }
}
