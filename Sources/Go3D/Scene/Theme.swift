/// The look of a set of stones.
struct StoneLook: Sendable {
    var albedo = Vec3.zero
    var roughness: Float = 0.3
    var metallic: Float = 0
    var clearcoat: Float = 0
    var clearcoatRoughness: Float = 0.05
    var subsurface: Float = 0
    var pattern: Float = 0 // 0 none, 1 shell, 2 slate, 3 glass, 4 yunzi
    var patternStrength: Float = 0
    var trim = Vec3.zero   // a glowing ring round the edge
    var trimStrength: Float = 0
    var edge = Vec3.zero   // light coming through the thin edge
    var edgeStrength: Float = 0
}

/// A soft box or a light strip of the studio round the board.
struct StudioPanel: Sendable {
    var direction = Vec3.zero // toward the panel
    var roll: Float = 0
    var halfSize = Vec2.zero  // as tangents of the angles
    var corner: Float = 0.05
    var softness: Float = 0.05
    var radiance = Vec3.zero
    var falloff: Float = 0.3
}

/// The looks of the set: the board, the stones, the bowls, the table and the studio light around them.
struct Theme: Sendable {
    var nameEnglish = ""
    var nameRussian = ""

    // The board.
    var boardColor = Vec3.zero
    var boardRoughness: Float = 0.3
    var boardClearcoat: Float = 0
    var boardClearcoatRoughness: Float = 0.05
    var boardPattern: Float = 0 // 0 kaya, 1 bamboo, 2 slate, 3 glass
    var reflection: Float = 0.5
    var reflectionBlur: Float = 1.5
    var gridColor = Vec3.zero
    var gridWidth: Float = 0.02 // half the width of a line
    var gridMetallic: Float = 0
    var gridRoughness: Float = 0.5
    var gridGlow: Float = 0
    var starRadius: Float = 0.09

    // The bowls and their lids.
    var bowlColor = Vec3.zero
    var bowlRoughness: Float = 0.35
    var bowlClearcoat: Float = 0.6
    var bowlPattern: Float = 0 // 0 wood, 1 lacquer
    var bowlSeed: Float = 0.3

    var white = StoneLook()
    var black = StoneLook()

    var tableColor = Vec3.zero
    var tableRoughness: Float = 0.9
    var tablePattern: Float = 0 // 0 felt, 1 wood, 2 glowing grid, 3 stone
    var tableSheen: Float = 0
    var tableGlow: Float = 0

    // The light.
    var keyDirection = Vec3.zero
    var keyRadiance = Vec3.zero
    var keySoftness: Float = 0.04 // tangent of the light's angular radius
    var ceiling = Vec3.zero, horizon = Vec3.zero, floor = Vec3.zero
    var panels: [StudioPanel] = []
    var diffuseLight: Float = 1
    var reflectedLight: Float = 1
    var background: Float = 0.6
    var fog = Vec3.zero
    var exposure: Float = 1
    var bloom: Float = 0.05
    var vignette: Float = 0.35

    var accent = Vec3.zero     // highlights and the interface
    var accentWarm = Vec3.zero // ko

    func name(_ language: Language) -> String { language == .russian ? nameRussian : nameEnglish }
}
