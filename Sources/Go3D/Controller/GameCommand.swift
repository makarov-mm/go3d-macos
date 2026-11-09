/// What the menus ask of the game; the raw value is the menu item's tag.
enum GameCommand: Int, CaseIterable {
    case newGame = 1
    case undo
    case redo
    case pass
    case resign
    case hint
    case estimate
    case accept
    case copyGame
    case pasteGame
    case flip
    case topView
    case resetView
    case panel
    case nextTheme
    case help
}
