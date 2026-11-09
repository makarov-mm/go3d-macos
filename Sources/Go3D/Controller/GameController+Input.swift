import AppKit

/// The virtual key codes of the keys the game reads by their place on the keyboard, whatever the layout.
private enum KeyCode {
    static let returnKey: UInt16 = 0x24
    static let tab: UInt16 = 0x30
    static let delete: UInt16 = 0x33
    static let escape: UInt16 = 0x35
    static let keypadEnter: UInt16 = 0x4C
    static let help: UInt16 = 0x72
    static let home: UInt16 = 0x73
    static let f1: UInt16 = 0x7A
    static let leftArrow: UInt16 = 0x7B
    static let rightArrow: UInt16 = 0x7C

    /// The letters and digits of the ANSI layout, for a key whose character in the layout in use is not one of them,
    /// as on a Russian keyboard.
    static let ansi: [UInt16: Character] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g", 0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v",
        0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x19: "9", 0x1A: "7", 0x1C: "8", 0x1D: "0", 0x1F: "o", 0x20: "u", 0x22: "i",
        0x23: "p", 0x25: "l", 0x26: "j", 0x28: "k", 0x2D: "n", 0x2E: "m",
        0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4", 0x57: "5", // the keypad
    ]
}

// The mouse, the trackpad and the keyboard.
extension GameController {
    // MARK: Events from the view, in pixels from the top left

    func pointerMoved(x: Float, y: Float) {
        pointer.x = x
        pointer.y = y
        requestFrame()
    }

    /// The pointer left the window: nothing stays highlighted under it, unless a button is held.
    func pointerExited() {
        if !pointer.leftDown && !pointer.rightDown {
            pointer.x = -1
            pointer.y = -1
        }
        requestFrame()
    }

    func buttonDown(right: Bool, x: Float, y: Float) {
        pointer.x = x
        pointer.y = y
        if right {
            pointer.rightDown = true
            pointer.rightPressed = true
        } else {
            pointer.leftDown = true
            pointer.leftPressed = true
        }
        requestFrame()
    }

    func buttonUp(right: Bool, x: Float, y: Float) {
        pointer.x = x
        pointer.y = y
        if right {
            pointer.rightDown = false
            pointer.rightReleased = true
        } else {
            pointer.leftDown = false
            pointer.leftReleased = true
        }
        requestFrame()
    }

    /// The window lost the mouse in the middle of a press: the buttons held count as released.
    func cancelPointer() {
        if pointer.leftDown {
            pointer.leftReleased = true
        }
        if pointer.rightDown {
            pointer.rightReleased = true
        }
        pointer.leftDown = false
        pointer.rightDown = false
        requestFrame()
    }

    /// Steps of a mouse wheel, positive away from the user; zooms in, or scrolls the moves under the pointer.
    func scrolled(_ steps: Float) {
        pointer.wheel += steps
        requestFrame()
    }

    /// A pinch on the trackpad, positive apart.
    func magnified(_ amount: Float) {
        camera.zoom(amount * 7)
        requestFrame()
    }

    /// Two fingers turning on the trackpad, counterclockwise for a positive angle: the board turns with them.
    func rotated(_ radians: Float) {
        camera.rotate(yaw: -radians, pitch: 0)
        requestFrame()
    }

    // MARK: The board

    /// The point where the ray under the pointer meets a level plane.
    private func pointerOnPlane(_ planeHeight: Float) -> Vec3 {
        let (origin, direction) = camera.ray(x: pointer.x, y: pointer.y, width: Float(pixelWidth), height: Float(pixelHeight))
        if abs(direction.y) < 1e-5 {
            return origin
        }
        let t = (planeHeight - origin.y) / direction.y
        return origin + direction * max(t, 0)
    }

    /// The point nearest the pointer, aimed at a little above the board, between its surface and the tops of the stones.
    private var pointUnderPointer: GoPoint {
        layout.point(near: pointerOnPlane(0.1))
    }

    /// Why a stone may not go on a point, for a toast.
    private func illegalReason(_ point: GoPoint) -> Str {
        let board = game.current
        if board.isStone(point) {
            return .occupied
        }
        if point == board.ko {
            return .koForbidden
        }
        if !board.isLegal(point, board.toPlay) {
            return .suicide
        }
        return .superko
    }

    func handleBoardPointer() {
        let blocked = pointer.consumed || helpVisible
        let playing = humanToMove && boardView.isBoardReady
        let counting = phase == .scoring && mode != .demo && !findingDead
        let inside = pointer.x >= 0 && pointer.y >= 0 && pointer.x < Float(pixelWidth) && pointer.y < Float(pixelHeight)
        let point = inside && !blocked ? pointUnderPointer : Go.pass

        // A legal point under the pointer, where a stone is shown seen through; while counting, a stone to mark.
        let hoverBefore = hoverPoint
        hoverPoint = Go.pass
        if point != Go.pass && (gesture == .none || gesture == .pressPoint) {
            if playing && game.isLegal(point) {
                hoverPoint = point
            } else if counting && game.current.isStone(point) {
                hoverPoint = point
            }
        }
        if hoverPoint != Go.pass {
            wantsHandCursor = true
        }
        if hoverPoint != hoverBefore {
            dirty = true // drawn again with the new point and the stones it would take
        }

        if !blocked && pointer.leftPressed {
            pressX = pointer.x
            dragX = pointer.x
            pressY = pointer.y
            dragY = pointer.y
            pressPoint = point
            gesture = hoverPoint != Go.pass ? .pressPoint : .turnCamera
        }
        if !pointer.consumed && pointer.rightPressed && gesture == .none {
            gesture = .turnCamera
            pressPoint = Go.pass
            pressX = pointer.x
            dragX = pointer.x
            pressY = pointer.y
            dragY = pointer.y
        }

        // A press on a point that moves on turns the view instead.
        let travel = abs(pointer.x - pressX) + abs(pointer.y - pressY)
        if gesture == .pressPoint && travel > 6 * scale && pointer.leftDown {
            gesture = .turnCamera
        }
        if gesture == .turnCamera {
            camera.rotate(yaw: -(pointer.x - dragX) * 0.0055 / scale, pitch: (pointer.y - dragY) * 0.0045 / scale)
            dragX = pointer.x
            dragY = pointer.y
        }

        if pointer.leftReleased || pointer.rightReleased {
            if gesture == .pressPoint && pointer.leftReleased && point == pressPoint {
                if playing && game.isLegal(point) {
                    playMove(point)
                } else if counting && game.current.isStone(point) {
                    game.toggleDead(point)
                    sound.play(.click)
                }
            } else if gesture == .turnCamera && pointer.leftReleased && travel < 4 * scale && playing && point != Go.pass && !game.isLegal(point) {
                showToast(tr(illegalReason(point))) // a click where a stone may not go
            }
            if (pointer.leftReleased && gesture != .none && !(gesture == .turnCamera && pointer.rightDown)) ||
                (pointer.rightReleased && gesture == .turnCamera && !pointer.leftDown) {
                gesture = .none
            }
        }

        if !pointer.consumed && pointer.wheel != 0 {
            camera.zoom(pointer.wheel)
        }
    }

    // MARK: The keyboard

    /// A key pressed in the game's window; false for one the game does not use. The letters are read in the layout
    /// in use, or by their place on the keyboard where it has no Latin letters.
    func keyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let code = event.keyCode
        let question = event.charactersIgnoringModifiers == "?" || event.characters == "?"
        let key = Self.keyCharacter(event) ?? " " // a space for a key without a letter or a digit
        requestFrame()

        if helpVisible && (code == KeyCode.escape || code == KeyCode.f1 || code == KeyCode.help || question) {
            helpVisible = false
            return true
        }
        if command {
            // The menus take these first; they come here when a menu's item is off, as Undo with nothing to undo.
            switch key {
            case "z": shift ? redo() : undo()
            case "y": redo()
            case "c": copyGame()
            case "v": pasteGame()
            case "n": newGame()
            default: return false
            }
            return true
        }
        if flags.contains(.control) || flags.contains(.option) {
            return false
        }

        // Only taking back and replaying go on while a key is held.
        switch code {
        case KeyCode.delete, KeyCode.leftArrow:
            undo()
            return true
        case KeyCode.rightArrow:
            redo()
            return true
        default:
            break
        }
        if event.isARepeat {
            return true
        }
        switch code {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            accept()
            return true
        case KeyCode.home:
            camera.reset(viewSide)
            return true
        case KeyCode.tab:
            togglePanel()
            return true
        case KeyCode.f1, KeyCode.help:
            helpVisible.toggle()
            return true
        case KeyCode.escape:
            if host?.isFullScreen == true {
                host?.toggleFullScreen()
            }
            return true
        default:
            break
        }
        if question {
            helpVisible.toggle()
            return true
        }

        switch key {
        case "p":
            if humanToMove {
                playMove(Go.pass)
            }
        case "n": newGame()
        case "h": requestHint()
        case "e": requestEstimate()
        case "f": camera.flip()
        case "v": camera.toggleTopView()
        case "m": setMode(mode.rawValue + (shift ? -1 : 1))
        case "b": stepBoardSize(shift ? -1 : 1, wrap: true)
        case "c": toggleCoordinates()
        case "t": setTheme(theme + (shift ? -1 : 1))
        case "s": toggleSound()
        case "l": toggleLanguage()
        case "a": host?.showAbout()
        case "1", "2", "3", "4", "5":
            setLevel(key.wholeNumberValue ?? level)
        default:
            return false
        }
        return true
    }

    /// The key's letter or digit, in lower case.
    private static func keyCharacter(_ event: NSEvent) -> Character? {
        if let text = event.charactersIgnoringModifiers?.lowercased(), text.count == 1, let character = text.first, character.isASCII,
           character.isLetter || character.isNumber {
            return character
        }
        return KeyCode.ansi[event.keyCode]
    }
}
