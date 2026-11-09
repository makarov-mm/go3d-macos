import Foundation

/// The interface's languages.
enum Language: Int, Sendable {
    case english = 0
    case russian = 1

    var other: Language { self == .english ? .russian : .english }
}

/// The interface's words in English and Russian. Every case has both, as the switch below makes sure.
enum Str: Sendable {
    case title, blackToMove, whiteToMove, thinking, counting, countingHelp, estimating, draw, blackWins, whiteWins
    case blackResigned, whiteResigned, scoreDetail, blackPasses, whitePasses, bothPassed
    case pass, resign, confirmResign, accept, resume, estimate, estimateToast
    case you, computer, player, black, white, captures, points, komi, moves, noMovesYet
    case undo, redo, hint, newGame, flip, mode, modeBlack, modeWhite, modeTwoPlayers, modeDemo
    case level, level1, level2, level3, level4, level5, board, handicap, noHandicap, stonesFew, stonesMany, nextGame
    case coordinates, theme, sound, languageName, footer, controls, keyClick, keyDrag, keyWheel
    case helpClick, helpRotate, helpZoom, helpUndo, helpRedo, helpPass, helpHint, helpEstimate, helpAccept, helpNew
    case helpFlip, helpTopView, helpLevel, helpMode, helpBoard, helpCoordinates, helpTheme, helpSound, helpLanguage
    case helpPanel, helpFullScreen, helpCopy, helpPaste, helpAbout, helpClose, rules, rulesNote
    case gameCopied, gameLoaded, nothingToPaste, hintToast, hintPass, nothingToUndo, occupied, koForbidden, suicide, superko
    // The menus.
    case menuAbout, menuHide, menuHideOthers, menuShowAll, menuQuit, menuGame, menuNewGame, menuUndo, menuRedo, menuPass
    case menuResign, menuHint, menuEstimate, menuAccept, menuCopy, menuPaste, menuView, menuFlip, menuTopView, menuResetView
    case menuPanel, menuTheme, menuFullScreen, menuWindow, menuMinimize, menuZoom, menuHelp, menuGameHelp, resignQuestion, cancel
    // The About window and the start.
    case aboutVersion, aboutDescription, aboutAuthor, aboutLinks, aboutSupport, aboutLicense, aboutClose, startFailed

    /// The level's name, 1 to 5.
    static func level(_ level: Int) -> Str { [.level1, .level2, .level3, .level4, .level5][min(max(level, 1), 5) - 1] }

    func text(_ language: Language) -> String {
        let (english, russian) = entry
        return language == .russian ? russian : english
    }

    private var entry: (String, String) {
        switch self {
        case .title: ("3D Go", "Го 3D")
        case .blackToMove: ("Black to play", "Ход чёрных")
        case .whiteToMove: ("White to play", "Ход белых")
        case .thinking: ("Computer is thinking…", "Компьютер думает…")
        case .counting: ("Counting", "Подсчёт очков")
        case .countingHelp: ("Click a group to mark it dead or alive", "Щелчок по группе: мёртвая / живая")
        case .estimating: ("Finding the dead stones…", "Ищу мёртвые камни…")
        case .draw: ("Jigo: a draw", "Ничья (дзиго)")
        case .blackWins: ("Black wins", "Чёрные победили")
        case .whiteWins: ("White wins", "Белые победили")
        case .blackResigned: ("Black resigned", "Чёрные сдались")
        case .whiteResigned: ("White resigned", "Белые сдались")
        case .scoreDetail: ("Black {} · White {} + {} komi", "Чёрные {} · белые {} + {} коми")
        case .blackPasses: ("Black passes", "Чёрные пасуют")
        case .whitePasses: ("White passes", "Белые пасуют")
        case .bothPassed: ("Both passed: time to count", "Оба спасовали — подсчёт очков")
        case .pass: ("Pass", "Пас")
        case .resign: ("Resign", "Сдаться")
        case .confirmResign: ("Sure?", "Точно?")
        case .accept: ("Accept", "Принять")
        case .resume: ("Play on", "Доиграть")
        case .estimate: ("Estimate", "Оценка")
        case .estimateToast: ("{} ahead by about {}", "{} впереди примерно на {}")
        case .you: ("You", "Вы")
        case .computer: ("Computer", "Компьютер")
        case .player: ("Player", "Игрок")
        case .black: ("Black", "Чёрные")
        case .white: ("White", "Белые")
        case .captures: ("prisoners", "пленные")
        case .points: ("points", "очки")
        case .komi: ("komi", "коми")
        case .moves: ("Moves", "Ходы")
        case .noMovesYet: ("No moves yet", "Ходов пока нет")
        case .undo: ("Undo", "Назад")
        case .redo: ("Redo", "Вперёд")
        case .hint: ("Hint", "Подсказка")
        case .newGame: ("New game", "Новая партия")
        case .flip: ("Flip board", "Развернуть")
        case .mode: ("Mode", "Режим")
        case .modeBlack: ("You play Black", "Вы за чёрных")
        case .modeWhite: ("You play White", "Вы за белых")
        case .modeTwoPlayers: ("Two players", "Два игрока")
        case .modeDemo: ("Demo game", "Демонстрация")
        case .level: ("Level", "Уровень")
        case .level1: ("Novice", "Новичок")
        case .level2: ("Beginner", "Начинающий")
        case .level3: ("Casual", "Любитель")
        case .level4: ("Strong", "Сильный")
        case .level5: ("Master", "Мастер")
        case .board: ("Board", "Доска")
        case .handicap: ("Handicap", "Фора")
        case .noHandicap: ("None", "Нет")
        case .stonesFew: ("{} stones", "{} камня")
        case .stonesMany: ("{} stones", "{} камней")
        case .nextGame: ("Applies from the next game (N)", "Вступит в силу в новой партии (N)")
        case .coordinates: ("Coordinates", "Координаты")
        case .theme: ("Theme", "Тема")
        case .sound: ("Sound", "Звук")
        case .languageName: ("English", "Русский")
        case .footer: ("? help · Tab panel · ⌃⌘F full screen", "? справка · Tab панель · ⌃⌘F весь экран")
        case .controls: ("Controls", "Управление")
        case .keyClick: ("Click", "Щелчок")
        case .keyDrag: ("Drag", "Перетаскивание")
        case .keyWheel: ("Scroll, pinch", "Прокрутка, щипок")
        case .helpClick: ("Place a stone; mark dead groups", "Поставить камень; отметить мёртвых")
        case .helpRotate: ("Turn the view (either button)", "Повернуть вид (любой кнопкой)")
        case .helpZoom: ("Zoom in and out", "Приблизить или отдалить")
        case .helpUndo: ("Take back", "Отменить ход")
        case .helpRedo: ("Replay", "Вернуть ход")
        case .helpPass: ("Pass", "Пас")
        case .helpHint: ("Suggest a move", "Подсказать ход")
        case .helpEstimate: ("Estimate the score", "Оценить положение")
        case .helpAccept: ("Accept the count", "Принять подсчёт")
        case .helpNew: ("New game", "Новая партия")
        case .helpFlip: ("Flip the board", "Развернуть доску")
        case .helpTopView: ("View from above", "Вид сверху")
        case .helpLevel: ("Computer level", "Уровень компьютера")
        case .helpMode: ("Who plays whom", "Кто с кем играет")
        case .helpBoard: ("Board size", "Размер доски")
        case .helpCoordinates: ("Coordinates", "Координаты")
        case .helpTheme: ("Next theme", "Следующая тема")
        case .helpSound: ("Sound on or off", "Звук вкл/выкл")
        case .helpLanguage: ("English / Russian", "Русский / английский")
        case .helpPanel: ("Show or hide the panel", "Показать/скрыть панель")
        case .helpFullScreen: ("Full screen", "Весь экран")
        case .helpCopy: ("Copy the game (SGF)", "Копировать партию (SGF)")
        case .helpPaste: ("Paste a game (SGF)", "Вставить партию (SGF)")
        case .helpAbout: ("About the game and its author", "Об игре и её авторе")
        case .helpClose: ("Close this help", "Закрыть справку")
        case .rules: ("Rules", "Правила")
        case .rulesNote:
            ("Black and White take turns placing stones where the lines cross. Stones of one color next to each other along the lines form a group; "
                + "a group with no empty point beside it is captured. A ko may not be retaken at once, and no move may bring back an earlier position. "
                + "Two passes in a row end the game: the dead groups are taken off, and each side counts its stones and the empty points they "
                + "surround. White gets komi: 7.5 points, or 0.5 with a handicap.",
             "Чёрные и белые по очереди ставят камни на пересечения линий. Камни одного цвета, соседние по линиям, образуют группу; группа без "
                + "свободных соседних пунктов снимается с доски. Ко нельзя отбить сразу же, и никакой ход не может повторить прежнюю позицию. "
                + "Два паса подряд завершают партию: мёртвые группы снимаются, и каждый считает свои камни и окружённые ими пустые пункты. "
                + "Белые получают коми: 7,5 очка, а при форе 0,5.")
        case .gameCopied: ("Game copied as SGF", "Партия скопирована (SGF)")
        case .gameLoaded: ("Game loaded", "Партия загружена")
        case .nothingToPaste: ("The clipboard has no SGF game", "В буфере нет партии в SGF")
        case .hintToast: ("Hint: ", "Подсказка: ")
        case .hintPass: ("Hint: pass", "Подсказка: пас")
        case .nothingToUndo: ("No moves to take back", "Нечего отменять")
        case .occupied: ("That point is taken", "Пункт занят")
        case .koForbidden: ("Ko: it may not be retaken at once", "Ко: сразу отбивать нельзя")
        case .suicide: ("Suicide is not allowed", "Самоубийственный ход запрещён")
        case .superko: ("Not allowed: the position would repeat", "Нельзя: позиция повторится")

        case .menuAbout: ("About 3D Go", "Об игре «Го 3D»")
        case .menuHide: ("Hide 3D Go", "Скрыть «Го 3D»")
        case .menuHideOthers: ("Hide Others", "Скрыть остальные")
        case .menuShowAll: ("Show All", "Показать все")
        case .menuQuit: ("Quit 3D Go", "Завершить «Го 3D»")
        case .menuGame: ("Game", "Партия")
        case .menuNewGame: ("New Game", "Новая партия")
        case .menuUndo: ("Take Back", "Отменить ход")
        case .menuRedo: ("Replay", "Вернуть ход")
        case .menuPass: ("Pass", "Пас")
        case .menuResign: ("Resign", "Сдаться")
        case .menuHint: ("Suggest a Move", "Подсказать ход")
        case .menuEstimate: ("Estimate the Score", "Оценить положение")
        case .menuAccept: ("Accept the Count", "Принять подсчёт")
        case .menuCopy: ("Copy the Game (SGF)", "Копировать партию (SGF)")
        case .menuPaste: ("Paste a Game (SGF)", "Вставить партию (SGF)")
        case .menuView: ("View", "Вид")
        case .menuFlip: ("Flip the Board", "Развернуть доску")
        case .menuTopView: ("View from Above", "Вид сверху")
        case .menuResetView: ("Reset the View", "Сбросить вид")
        case .menuPanel: ("Show or Hide the Panel", "Показать или скрыть панель")
        case .menuTheme: ("Next Theme", "Следующая тема")
        case .menuFullScreen: ("Full Screen", "Весь экран")
        case .menuWindow: ("Window", "Окно")
        case .menuMinimize: ("Minimize", "Свернуть")
        case .menuZoom: ("Zoom", "Изменить масштаб")
        case .menuHelp: ("Help", "Справка")
        case .menuGameHelp: ("3D Go Help", "Справка «Го 3D»")
        case .resignQuestion: ("Resign this game?", "Сдаться в этой партии?")
        case .cancel: ("Cancel", "Отмена")

        case .aboutVersion: ("Version {}", "Версия {}")
        case .aboutDescription:
            ("A game of Go in 3D for macOS, written in Swift on AppKit and Metal. There is no game engine, no third-party library and no model, "
                + "texture or sound file: the stones, the bowls and their lids are turned on a lathe in code, the wood, slate, shell and glass "
                + "are procedural, the studio light is baked on the GPU, and the sounds are synthesized. The computer opponent plays with a "
                + "Monte Carlo tree search at five levels.",
             "Игра го в 3D для macOS, написанная на Swift с AppKit и Metal. В ней нет игрового движка, сторонних библиотек, моделей, текстур и "
                + "звуковых файлов: камни, чаши и крышки вытачиваются в коде, дерево, сланец, ракушка и стекло процедурные, студийный свет "
                + "запекается на видеокарте, а звуки синтезируются. Компьютер играет поиском по дереву методом Монте-Карло, на пяти уровнях.")
        case .aboutAuthor: ("Created by Mykhailo Makarov", "Автор: Mykhailo Makarov")
        case .aboutLinks: ("Find me on", "Где меня найти")
        case .aboutSupport: ("If you enjoy the game, you can support my work on GitHub Sponsors.",
                             "Если игра вам понравилась, поддержать мою работу можно на GitHub Sponsors.")
        case .aboutLicense: ("© 2026 Mykhailo Makarov · MIT License", "© 2026 Mykhailo Makarov · лицензия MIT")
        case .aboutClose: ("Close", "Закрыть")
        case .startFailed: ("3D Go cannot start", "«Го 3D» не запускается")
        }
    }
}

/// The text with each "{}" replaced by the next argument.
func format(_ template: String, _ arguments: String...) -> String {
    var result = ""
    var rest = Substring(template)
    var remaining = arguments[...]
    while let range = rest.range(of: "{}"), let argument = remaining.popFirst() {
        result += rest[..<range.lowerBound]
        result += argument
        rest = rest[range.upperBound...]
    }
    return result + rest
}
