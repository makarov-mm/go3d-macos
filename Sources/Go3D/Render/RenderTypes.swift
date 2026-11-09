/// A stone, in the look of its color.
struct StoneDraw {
    var model = Mat4.identity
    var white = false
    /// The height of what it lies on.
    var ground: Float = 0
    var glowColor = Vec3.zero
    var glow: Float = 0
    var dissolve: Float = 0
    /// Where the pattern falls.
    var seed: Float = 0
    /// The ring on the stone played last.
    var mark: Float = 0
    /// Below 1, seen through: a dead stone, or where a click would play.
    var opacity: Float = 1
}

/// What is marked on each point of the board, as bits; see the surface shader.
enum SceneMark {
    static let blackArea: UInt8 = 1
    static let whiteArea: UInt8 = 2
    static let hover: UInt8 = 4
    static let hint: UInt8 = 8
    static let ko: UInt8 = 16
    static let stoneHere: UInt8 = 32
}

/// A rectangle of the screen behind which the scene is blurred, in pixels from the top left.
struct FrostedPanel {
    var x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0, radius: Float = 0, opacity: Float = 1
}

struct RenderScene {
    var view = Mat4.identity
    var projection = Mat4.identity
    var eye = Vec3.zero
    var time: Float = 0
    var stones: [StoneDraw] = []
    /// Column + maxSize × row, the rows from the far side; padded to a whole number of words.
    var marks = [UInt8](repeating: 0, count: 364)
    /// The territory marked as an estimate, fainter.
    var estimate = false
    var coordinates = true
    var panels: [FrostedPanel] = []
}

// The data the shaders read, laid out as the structures of the same names in the Metal source: every member is a
// float4, uint4 or float4x4, so that Swift and Metal agree on the layout.

struct FrameData {
    var viewProjection = Mat4.identity
    var inverseViewProjection = Mat4.identity
    var lightViewProjection = Mat4.identity
    var cameraPosition = Vec4.zero
    var lightDirection = Vec4.zero
    var lightColor = Vec4.zero
    var shadowParams = Vec4.zero
    var viewport = Vec4.zero
    var environment = Vec4.zero
    var accent = Vec4.zero
    var accentWarm = Vec4.zero
    var fog = Vec4.zero
}

struct PassData {
    var eye = Vec4.zero
    var mirror = Vec4.zero
}

struct StoneInstance {
    var model: Mat4
    var glow: Vec4
    var params: Vec4
    var extra: Vec4
}

struct StoneMaterial {
    var albedo = Vec4.zero
    var surface = Vec4.zero
    var style = Vec4.zero
    var trim = Vec4.zero
    var edge = Vec4.zero
}

struct SurfaceMaterial {
    var boardColor = Vec4.zero
    var boardSurface = Vec4.zero
    var boardReflection = Vec4.zero
    var gridColor = Vec4.zero
    var grid = Vec4.zero
    var boardShape = Vec4.zero
    var bowlColor = Vec4.zero
    var bowlSurface = Vec4.zero
    var tableColor = Vec4.zero
    var tableSurface = Vec4.zero
    var tableFade = Vec4.zero
    var markStyle = Vec4.zero
    var discs: (Vec4, Vec4, Vec4, Vec4) = (.zero, .zero, .zero, .zero)
}

struct SurfaceDraw {
    var model = Mat4.identity
    var bowlShape = Vec4.zero
    var kind = Vec4.zero
}

struct CompositeParams {
    var settings = Vec4.zero
    var viewport = Vec4.zero
    var panels: (Vec4, Vec4, Vec4, Vec4) = (.zero, .zero, .zero, .zero)
    var panelStyles: (Vec4, Vec4, Vec4, Vec4) = (.zero, .zero, .zero, .zero)
}

struct EnvironmentParams {
    var ceilingColor = Vec4.zero
    var horizonColor = Vec4.zero
    var floorColor = Vec4.zero
    var counts = SIMD4<UInt32>.zero
}

extension SIMD3 where Scalar == Float {
    /// The color as a float4 with an alpha of 1, for the shaders.
    var color4: Vec4 { Vec4(x, y, z, 1) }
}
