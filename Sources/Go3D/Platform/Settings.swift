import Foundation

/// The choices and the game in progress, kept between sessions in the user defaults. The window's frame is kept by
/// AppKit under its autosave name.
struct Settings {
    var theme = 0
    var level = 2
    var mode = 0
    var boardSize = 9 // for new games
    var handicap = 0  // for new games
    var coordinates = true
    var sound = true
    var panel = true
    var language = Language.english
    var game = "" // in SGF

    private enum Key {
        static let theme = "Theme", level = "Level", mode = "Mode", boardSize = "BoardSize", handicap = "Handicap"
        static let coordinates = "Coordinates", sound = "Sound", panel = "Panel", language = "Language", game = "Game"
    }

    static func load(from defaults: UserDefaults = .standard) -> Settings {
        func integer(_ key: String) -> Int? { defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key) }
        func boolean(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
        var settings = Settings()
        settings.theme = min(max(integer(Key.theme) ?? 0, 0), Themes.all.count - 1)
        settings.level = min(max(integer(Key.level) ?? 2, 1), 5)
        settings.mode = min(max(integer(Key.mode) ?? 0, 0), 3)
        let size = integer(Key.boardSize) ?? 9
        settings.boardSize = size == 13 || size == 19 ? size : 9
        settings.handicap = min(max(integer(Key.handicap) ?? 0, 0), 9)
        if settings.handicap == 1 || settings.handicap > Go.maxHandicap(size: settings.boardSize) {
            settings.handicap = 0
        }
        settings.coordinates = boolean(Key.coordinates) ?? true
        settings.sound = boolean(Key.sound) ?? true
        settings.panel = boolean(Key.panel) ?? true
        settings.language = integer(Key.language).flatMap(Language.init(rawValue:)) ?? systemLanguage()
        settings.game = defaults.string(forKey: Key.game) ?? ""
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(theme, forKey: Key.theme)
        defaults.set(level, forKey: Key.level)
        defaults.set(mode, forKey: Key.mode)
        defaults.set(boardSize, forKey: Key.boardSize)
        defaults.set(handicap, forKey: Key.handicap)
        defaults.set(coordinates, forKey: Key.coordinates)
        defaults.set(sound, forKey: Key.sound)
        defaults.set(panel, forKey: Key.panel)
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set(game, forKey: Key.game)
    }

    /// Russian for the languages of the former Soviet Union in which most read Russian, English for the rest.
    private static func systemLanguage() -> Language {
        let code = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return ["ru", "uk", "be"].contains(code) ? .russian : .english
    }
}
