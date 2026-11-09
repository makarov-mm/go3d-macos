import AppKit
import MetalKit

/// The window's view: Metal draws the game into it, a frame each time the display refreshes while anything moves, and
/// it passes the mouse, the trackpad and the keyboard on to the game.
final class GameView: MTKView {
    weak var controller: GameController?
    private var handCursor = false

    override init(frame frameRect: CGRect, device: (any MTLDevice)?) {
        super.init(frame: frameRect, device: device)
        colorPixelFormat = Renderer.drawableFormat
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        framebufferOnly = true
        autoResizeDrawable = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 120 // as fast as the display goes, up to ProMotion
        clearColor = MTLClearColor(red: 0.016, green: 0.017, blue: 0.022, alpha: 1)
        layer?.isOpaque = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init(coder: NSCoder) {
        fatalError("GameView is made in code.")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        controller?.drawFrame()
    }

    // MARK: Size

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        controller?.requestFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        controller?.requestFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.requestFrame()
    }

    // MARK: The cursor

    /// A hand over what can be clicked, an arrow elsewhere.
    func showHandCursor(_ hand: Bool) {
        guard hand != handCursor else { return }
        handCursor = hand
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: handCursor ? .pointingHand : .arrow)
    }

    // MARK: The mouse and the trackpad

    /// The event's place in pixels of the drawable, from the top left.
    private func location(_ event: NSEvent) -> (x: Float, y: Float) {
        let point = convert(event.locationInWindow, from: nil)
        let pixels = bounds.width > 0 ? drawableSize.width / bounds.width : 1
        return (Float(point.x * pixels), Float((bounds.height - point.y) * pixels))
    }

    override func mouseMoved(with event: NSEvent) {
        let at = location(event)
        controller?.pointerMoved(x: at.x, y: at.y)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        controller?.pointerExited()
    }

    override func mouseDown(with event: NSEvent) {
        let at = location(event)
        controller?.buttonDown(right: false, x: at.x, y: at.y)
    }

    override func mouseUp(with event: NSEvent) {
        let at = location(event)
        controller?.buttonUp(right: false, x: at.x, y: at.y)
    }

    override func rightMouseDown(with event: NSEvent) {
        let at = location(event)
        controller?.buttonDown(right: true, x: at.x, y: at.y)
    }

    override func rightMouseUp(with event: NSEvent) {
        let at = location(event)
        controller?.buttonUp(right: true, x: at.x, y: at.y)
    }

    /// A mouse wheel moves in lines, about one a notch; a trackpad or a Magic Mouse in points, many at a time.
    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        guard delta != 0 else { return }
        let at = location(event)
        controller?.pointerMoved(x: at.x, y: at.y)
        controller?.scrolled(event.hasPreciseScrollingDeltas ? delta / 40 : delta)
    }

    override func magnify(with event: NSEvent) {
        controller?.magnified(Float(event.magnification))
    }

    override func rotate(with event: NSEvent) {
        controller?.rotated(Float(event.rotation) * .pi / 180)
    }

    // MARK: The keyboard

    override func keyDown(with event: NSEvent) {
        if controller?.keyDown(event) == true {
            return
        }
        // A key the game does not use: a beep for a shortcut, silence for the rest.
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
        }
    }
}
