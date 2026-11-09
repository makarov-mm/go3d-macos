/// The four themes: Kaya with slate and shell stones, Bamboo with Chinese yunzi stones, Glass, and Neon.
enum Themes {
    static let all = [kaya(), bamboo(), glass(), neon()]

    static func at(_ index: Int) -> Theme { all[(index % all.count + all.count) % all.count] }

    /// A kaya board with slate and shell stones, dark mulberry bowls, a dark wooden table.
    private static func kaya() -> Theme {
        var t = Theme()
        t.nameEnglish = "Kaya"
        t.nameRussian = "Кая"
        t.boardColor = Vec3(0.64, 0.39, 0.13)
        t.boardRoughness = 0.42
        t.boardClearcoat = 0.3
        t.boardClearcoatRoughness = 0.12
        t.boardPattern = 0
        t.reflection = 0.18
        t.reflectionBlur = 2.6
        t.gridColor = Vec3(0.012, 0.009, 0.006)
        t.gridWidth = 0.021
        t.gridRoughness = 0.55
        t.starRadius = 0.095
        t.bowlColor = Vec3(0.15, 0.072, 0.03)
        t.bowlRoughness = 0.34
        t.bowlClearcoat = 0.75
        t.bowlPattern = 0
        t.bowlSeed = 0.37
        t.white = StoneLook(albedo: Vec3(0.84, 0.83, 0.79), roughness: 0.26, clearcoat: 0.55, clearcoatRoughness: 0.07, subsurface: 0.22,
                            pattern: 1, patternStrength: 1)
        t.black = StoneLook(albedo: Vec3(0.024, 0.024, 0.027), roughness: 0.44, clearcoat: 0.3, clearcoatRoughness: 0.22, pattern: 2,
                            patternStrength: 1)
        t.tableColor = Vec3(0.055, 0.032, 0.018)
        t.tableRoughness = 0.5
        t.tablePattern = 1
        t.keyDirection = Vec3(-0.5, 0.78, 0.38)
        t.keyRadiance = Vec3(4.2, 3.9, 3.4)
        t.keySoftness = 0.045
        t.ceiling = Vec3(0.035, 0.034, 0.034)
        t.horizon = Vec3(0.1, 0.085, 0.07)
        t.floor = Vec3(0.02, 0.016, 0.012)
        t.diffuseLight = 0.75
        t.reflectedLight = 1
        t.background = 0.55
        t.fog = Vec3(0.032, 0.027, 0.022)
        t.exposure = 1.05
        t.bloom = 0.035
        t.vignette = 0.42
        t.accent = Vec3(0.3, 0.72, 1)
        t.accentWarm = Vec3(1, 0.42, 0.18)
        t.panels = [
            StudioPanel(direction: Vec3(-0.5, 0.78, 0.38), halfSize: Vec2(0.42, 0.3), corner: 0.08, softness: 0.06, radiance: Vec3(7, 6.4, 5.6)),
            StudioPanel(direction: Vec3(0.85, 0.3, 0.3), halfSize: Vec2(0.55, 0.35), corner: 0.1, softness: 0.15, radiance: Vec3(0.7, 0.78, 0.9)),
            StudioPanel(direction: Vec3(0.15, 0.42, -0.9), halfSize: Vec2(1.3, 0.07), corner: 0.03, softness: 0.03, radiance: Vec3(5, 4.6, 4)),
            StudioPanel(direction: Vec3(0, 1, 0.05), halfSize: Vec2(0.7, 0.7), corner: 0.3, softness: 0.3, radiance: Vec3(0.6, 0.58, 0.55)),
            StudioPanel(direction: Vec3(-0.9, 0.25, -0.4), halfSize: Vec2(0.06, 0.6), corner: 0.03, softness: 0.03, radiance: Vec3(2.6, 2.2, 1.8)),
        ]
        return t
    }

    /// A board of laminated bamboo with Chinese yunzi stones, red lacquer bowls and green felt.
    private static func bamboo() -> Theme {
        var t = Theme()
        t.nameEnglish = "Bamboo · Yunzi"
        t.nameRussian = "Бамбук · юньцзы"
        t.boardColor = Vec3(0.6, 0.41, 0.19)
        t.boardRoughness = 0.34
        t.boardClearcoat = 0.5
        t.boardClearcoatRoughness = 0.08
        t.boardPattern = 1
        t.reflection = 0.35
        t.reflectionBlur = 2
        t.gridColor = Vec3(0.022, 0.012, 0.006)
        t.gridWidth = 0.019
        t.gridRoughness = 0.45
        t.starRadius = 0.09
        t.bowlColor = Vec3(0.3, 0.025, 0.018)
        t.bowlRoughness = 0.22
        t.bowlClearcoat = 0.9
        t.bowlPattern = 1
        t.bowlSeed = 0.71
        t.white = StoneLook(albedo: Vec3(0.78, 0.77, 0.68), roughness: 0.48, clearcoat: 0.18, clearcoatRoughness: 0.18, subsurface: 0.4,
                            pattern: 4, patternStrength: 1, edge: Vec3(0.55, 0.5, 0.36), edgeStrength: 0.25)
        t.black = StoneLook(albedo: Vec3(0.02, 0.025, 0.021), roughness: 0.46, clearcoat: 0.15, clearcoatRoughness: 0.2, pattern: 4,
                            patternStrength: 1, edge: Vec3(0.04, 0.3, 0.09), edgeStrength: 0.7)
        t.tableColor = Vec3(0.016, 0.045, 0.036)
        t.tableRoughness = 0.95
        t.tablePattern = 0
        t.tableSheen = 0.35
        t.keyDirection = Vec3(-0.58, 0.72, 0.4)
        t.keyRadiance = Vec3(4.4, 4, 3.4)
        t.keySoftness = 0.05
        t.ceiling = Vec3(0.035, 0.033, 0.032)
        t.horizon = Vec3(0.1, 0.085, 0.065)
        t.floor = Vec3(0.018, 0.016, 0.012)
        t.diffuseLight = 0.7
        t.reflectedLight = 1
        t.background = 0.55
        t.fog = Vec3(0.03, 0.028, 0.022)
        t.exposure = 1.05
        t.bloom = 0.04
        t.vignette = 0.42
        t.accent = Vec3(0.3, 0.92, 0.62)
        t.accentWarm = Vec3(1, 0.45, 0.15)
        t.panels = [
            StudioPanel(direction: Vec3(-0.58, 0.72, 0.4), halfSize: Vec2(0.42, 0.3), corner: 0.08, softness: 0.06, radiance: Vec3(7.4, 6.5, 5.4)),
            StudioPanel(direction: Vec3(0.85, 0.3, 0.3), halfSize: Vec2(0.55, 0.35), corner: 0.1, softness: 0.15, radiance: Vec3(0.65, 0.8, 0.75)),
            StudioPanel(direction: Vec3(0.15, 0.42, -0.9), halfSize: Vec2(1.3, 0.07), corner: 0.03, softness: 0.03, radiance: Vec3(5, 4.6, 4)),
            StudioPanel(direction: Vec3(0, 1, 0.05), halfSize: Vec2(0.7, 0.7), corner: 0.3, softness: 0.3, radiance: Vec3(0.6, 0.58, 0.52)),
            StudioPanel(direction: Vec3(-0.9, 0.25, -0.4), halfSize: Vec2(0.06, 0.6), corner: 0.03, softness: 0.03, radiance: Vec3(2.4, 2.1, 1.7)),
        ]
        return t
    }

    /// Smoked glass with silver lines, glass stones, black lacquer, a stone table.
    private static func glass() -> Theme {
        var t = Theme()
        t.nameEnglish = "Glass"
        t.nameRussian = "Стекло"
        t.boardColor = Vec3(0.011, 0.013, 0.017)
        t.boardRoughness = 0.07
        t.boardClearcoat = 1
        t.boardClearcoatRoughness = 0.03
        t.boardPattern = 3
        t.reflection = 1
        t.reflectionBlur = 0.7
        t.gridColor = Vec3(0.78, 0.8, 0.84)
        t.gridWidth = 0.015
        t.gridMetallic = 1
        t.gridRoughness = 0.22
        t.starRadius = 0.08
        t.bowlColor = Vec3(0.012, 0.012, 0.014)
        t.bowlRoughness = 0.1
        t.bowlClearcoat = 1
        t.bowlPattern = 1
        t.bowlSeed = 0.2
        t.white = StoneLook(albedo: Vec3(0.84, 0.86, 0.9), roughness: 0.2, clearcoat: 0.9, clearcoatRoughness: 0.03, subsurface: 0.5,
                            pattern: 3, patternStrength: 0.5, edge: Vec3(0.55, 0.66, 0.85), edgeStrength: 0.35)
        t.black = StoneLook(albedo: Vec3(0.008, 0.009, 0.013), roughness: 0.06, clearcoat: 1, clearcoatRoughness: 0.02, pattern: 3,
                            patternStrength: 0.6, edge: Vec3(0.06, 0.12, 0.35), edgeStrength: 0.6)
        t.tableColor = Vec3(0.024, 0.024, 0.028)
        t.tableRoughness = 0.3
        t.tablePattern = 3
        t.keyDirection = Vec3(-0.42, 0.85, 0.32)
        t.keyRadiance = Vec3(3.1, 3.15, 3.3)
        t.keySoftness = 0.05
        t.ceiling = Vec3(0.05, 0.055, 0.065)
        t.horizon = Vec3(0.09, 0.095, 0.11)
        t.floor = Vec3(0.018, 0.018, 0.02)
        t.diffuseLight = 1
        t.reflectedLight = 1
        t.background = 0.5
        t.fog = Vec3(0.03, 0.032, 0.038)
        t.exposure = 1
        t.bloom = 0.04
        t.vignette = 0.4
        t.accent = Vec3(0.4, 0.78, 1)
        t.accentWarm = Vec3(0.95, 0.6, 0.3)
        t.panels = [
            StudioPanel(direction: Vec3(-0.42, 0.85, 0.32), halfSize: Vec2(0.5, 0.5), corner: 0.25, softness: 0.12, radiance: Vec3(6, 6.1, 6.4)),
            StudioPanel(direction: Vec3(0.9, 0.2, 0.25), halfSize: Vec2(0.5, 0.3), corner: 0.1, softness: 0.12, radiance: Vec3(0.8, 0.85, 1)),
            StudioPanel(direction: Vec3(-0.1, 0.35, -0.92), halfSize: Vec2(1.4, 0.05), corner: 0.02, softness: 0.02, radiance: Vec3(6, 6.2, 6.6)),
            StudioPanel(direction: Vec3(0, 1, 0), halfSize: Vec2(0.8, 0.8), corner: 0.4, softness: 0.35, radiance: Vec3(0.9, 0.92, 1)),
            StudioPanel(direction: Vec3(0.6, 0.3, -0.75), halfSize: Vec2(0.05, 0.7), corner: 0.02, softness: 0.02, radiance: Vec3(2.5, 2.6, 3)),
        ]
        return t
    }

    /// A dark board with glowing lines and stones with neon rims.
    private static func neon() -> Theme {
        var t = Theme()
        t.nameEnglish = "Neon"
        t.nameRussian = "Неон"
        t.boardColor = Vec3(0.006, 0.008, 0.014)
        t.boardRoughness = 0.12
        t.boardClearcoat = 0.6
        t.boardClearcoatRoughness = 0.03
        t.boardPattern = 3
        t.reflection = 0.9
        t.reflectionBlur = 0.6
        t.gridColor = Vec3(0.2, 0.8, 1)
        t.gridWidth = 0.013
        t.gridRoughness = 0.3
        t.gridGlow = 1.6
        t.starRadius = 0.075
        t.bowlColor = Vec3(0.05, 0.055, 0.07)
        t.bowlRoughness = 0.25
        t.bowlClearcoat = 0.8
        t.bowlPattern = 1
        t.bowlSeed = 0.5
        t.white = StoneLook(albedo: Vec3(0.82, 0.86, 0.9), roughness: 0.2, clearcoat: 1, clearcoatRoughness: 0.03, subsurface: 0.5,
                            trim: Vec3(1, 0.3, 0.75), trimStrength: 5)
        t.black = StoneLook(albedo: Vec3(0.03, 0.032, 0.04), roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.03, pattern: 3,
                            patternStrength: 0.4, trim: Vec3(0.2, 0.8, 1), trimStrength: 5)
        t.tableColor = Vec3(0.004, 0.006, 0.01)
        t.tableRoughness = 0.5
        t.tablePattern = 2
        t.tableGlow = 0.5
        t.keyDirection = Vec3(-0.35, 0.8, 0.48)
        t.keyRadiance = Vec3(1.9, 2.2, 2.7)
        t.keySoftness = 0.03
        t.ceiling = Vec3(0.01, 0.012, 0.025)
        t.horizon = Vec3(0.02, 0.035, 0.07)
        t.floor = Vec3(0.004, 0.005, 0.008)
        t.diffuseLight = 1
        t.reflectedLight = 1.2
        t.background = 0.7
        t.fog = Vec3(0.006, 0.01, 0.02)
        t.exposure = 1.1
        t.bloom = 0.07
        t.vignette = 0.5
        t.accent = Vec3(0.2, 0.85, 1)
        t.accentWarm = Vec3(1, 0.35, 0.75)
        t.panels = [
            StudioPanel(direction: Vec3(-0.35, 0.8, 0.48), halfSize: Vec2(0.35, 0.25), corner: 0.05, softness: 0.05, radiance: Vec3(3.5, 4.2, 5)),
            StudioPanel(direction: Vec3(0.95, 0.12, 0.2), halfSize: Vec2(1, 0.03), corner: 0.02, softness: 0.02, radiance: Vec3(8, 1.5, 5)),
            StudioPanel(direction: Vec3(-0.95, 0.12, -0.2), halfSize: Vec2(1, 0.03), corner: 0.02, softness: 0.02, radiance: Vec3(1, 5, 8)),
            StudioPanel(direction: Vec3(0.1, 0.3, -0.95), halfSize: Vec2(1.4, 0.025), corner: 0.01, softness: 0.015, radiance: Vec3(8, 4, 1)),
            StudioPanel(direction: Vec3(0, 1, 0), halfSize: Vec2(0.6, 0.6), corner: 0.3, softness: 0.3, radiance: Vec3(0.25, 0.3, 0.45)),
            StudioPanel(direction: Vec3(0.3, 0.25, 0.95), halfSize: Vec2(0.9, 0.025), corner: 0.01, softness: 0.015, radiance: Vec3(1, 6, 7)),
        ]
        return t
    }
}
