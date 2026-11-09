import Metal

/// Draws the interface: rounded panels, shadows, icons and text, in pixels from the window's top left corner. The
/// shapes are quads whose shader works out their coverage from a distance function, so they are sharp at any scale.
@MainActor
final class UiPainter {
    enum FontId: Int {
        case body
        case heading
        case display
    }

    /// A corner of a quad, laid out as InterfaceVertex in the shaders.
    private struct InterfaceVertex {
        var positionUv: Vec4 // xy: pixels from the top left, zw: uv
        var color: Vec4
        var shape: Vec4      // x: what is drawn (see the shader); yzw depend on it
    }

    private let pipeline: any MTLRenderPipelineState
    private let buffers: BufferRing
    private var vertices: [InterfaceVertex] = []
    private var fonts: [FontAtlas] = []
    private var width: Float = 1, height: Float = 1

    init(shaders: ShaderLibrary) throws {
        pipeline = try shaders.renderPipeline("interface", vertex: "interfaceVertex", fragment: "interfaceFragment", color: Renderer.drawableFormat,
                                              blending: .interface)
        buffers = BufferRing(device: shaders.device)
    }

    /// The body, heading and display fonts.
    func setFonts(_ body: FontAtlas, _ heading: FontAtlas, _ display: FontAtlas) {
        fonts = [body, heading, display]
    }

    func font(_ id: FontId) -> FontAtlas { fonts[id.rawValue] }

    func begin(width: Int, height: Int) {
        self.width = Float(max(width, 1))
        self.height = Float(max(height, 1))
        vertices.removeAll(keepingCapacity: true)
    }

    // MARK: Shapes

    func fill(_ rect: UiRect, radius: Float, _ color: UiColor) {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        shape(rect, margin: 1, color, Vec4(3, rect.width / 2, rect.height / 2, radius))
    }

    func outline(_ rect: UiRect, radius: Float, _ color: UiColor) {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        shape(rect, margin: 1, color, Vec4(5, rect.width / 2, rect.height / 2, radius))
    }

    func shadow(_ rect: UiRect, blur: Float, _ color: UiColor) {
        shape(rect, margin: blur * 1.5, color, Vec4(4, rect.width / 2, rect.height / 2, blur))
    }

    func disc(x: Float, y: Float, radius: Float, _ color: UiColor) {
        shape(UiRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), margin: 1, color, Vec4(7, radius, 0, 0))
    }

    func spinner(x: Float, y: Float, radius: Float, thickness: Float, angle: Float, _ color: UiColor) {
        shape(UiRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), margin: thickness, color, Vec4(6, radius, thickness, angle))
    }

    /// A small triangle pointing left (direction -1) or right (1).
    func arrow(x: Float, y: Float, halfWidth: Float, halfHeight: Float, direction: Float, _ color: UiColor) {
        shape(UiRect(x: x - halfWidth, y: y - halfHeight, width: halfWidth * 2, height: halfHeight * 2), margin: 1, color,
              Vec4(8, halfWidth, halfHeight, direction))
    }

    // MARK: Text

    /// Text whose line starts at the top left point; returns its width.
    @discardableResult
    func text(_ id: FontId, x: Float, y: Float, _ text: String, _ color: UiColor) -> Float {
        let font = font(id)
        let kind = Float(id.rawValue)
        var pen = x.rounded()
        let top = y.rounded()
        for character in text.unicodeScalars {
            let glyph = font.glyph(character)
            let left = (pen + glyph.left).rounded(), glyphTop = top + glyph.top
            if glyph.width > 0 {
                quad(left, glyphTop, left + glyph.width, glyphTop + glyph.height, glyph.u0, glyph.v0, glyph.u1, glyph.v1, color, Vec4(kind, 0, 0, 0))
            }
            pen += glyph.advance
        }
        return pen - x.rounded()
    }

    func textCentered(_ id: FontId, _ rect: UiRect, _ text: String, _ color: UiColor) {
        let width = measure(id, text)
        let height = font(id).ascent
        self.text(id, x: rect.x + (rect.width - width) / 2, y: rect.y + (rect.height - height) / 2 - height * 0.04, text, color)
    }

    func measure(_ id: FontId, _ text: String) -> Float { font(id).measure(text) }
    func lineHeight(_ id: FontId) -> Float { font(id).lineHeight }

    // MARK: Drawing

    /// Draws what has been queued into the window's final pass.
    func flush(into encoder: any MTLRenderCommandEncoder) {
        guard !vertices.isEmpty, fonts.count == 3 else { return }
        let length = vertices.count * MemoryLayout<InterfaceVertex>.stride
        guard let buffer = buffers.next(length: length) else { return }
        vertices.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        var screen = Vec4(width, height, 0, 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&screen, length: MemoryLayout<Vec4>.stride, index: 1)
        for (index, font) in fonts.enumerated() {
            encoder.setFragmentTexture(font.texture, index: index)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        vertices.removeAll(keepingCapacity: true)
    }

    private func quad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ u0: Float, _ v0: Float, _ u1: Float, _ v1: Float, _ color: UiColor, _ shape: Vec4) {
        let c = color.vector
        let a = InterfaceVertex(positionUv: Vec4(x0, y0, u0, v0), color: c, shape: shape)
        let b = InterfaceVertex(positionUv: Vec4(x1, y0, u1, v0), color: c, shape: shape)
        let d = InterfaceVertex(positionUv: Vec4(x1, y1, u1, v1), color: c, shape: shape)
        let e = InterfaceVertex(positionUv: Vec4(x0, y1, u0, v1), color: c, shape: shape)
        vertices += [a, b, d, a, d, e]
    }

    /// A quad round a rectangle, its uv the position from the rectangle's center, for the distance shapes.
    private func shape(_ rect: UiRect, margin: Float, _ color: UiColor, _ shape: Vec4) {
        let halfWidth = rect.width / 2, halfHeight = rect.height / 2
        quad(rect.x - margin, rect.y - margin, rect.right + margin, rect.bottom + margin, -halfWidth - margin, -halfHeight - margin,
             halfWidth + margin, halfHeight + margin, color, shape)
    }
}
