import AppKit
import CoreText

/// The coordinates written round the lines of a board, drawn by Core Text.
enum BoardLabels {
    /// Coverage over the square from -boardHalf to boardHalf in x and z, one byte a pixel, the rows from -z; the outer
    /// lines are `half` from the middle. Each side's labels read upright from the nearer player's side: Black's along
    /// +z and on the left, White's turned half round on the far side and the right.
    @MainActor
    static func render(size: Int, lines: Int, half: Float, boardHalf: Float) -> [UInt8] {
        var coverage = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return coverage }
        let pixelsPerUnit = Float(size) / (2 * boardHalf)
        let height = CGFloat(Int(0.36 * pixelsPerUnit))
        let middle = (half + boardHalf) / 2 - 0.03
        func toPixel(_ world: Float) -> CGFloat { CGFloat(((world + boardHalf) * pixelsPerUnit).rounded()) }

        let font = NSFont.systemFont(ofSize: height, weight: .semibold) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        // Half the height of the capitals, in world units, by which the characters are centered on their points.
        let halfCap = Float(CTFontGetCapHeight(font)) * 0.5 / pixelsPerUnit
        context.setFillColor(gray: 1, alpha: 1)

        func draw(_ text: String, _ x: Float, _ z: Float, nearSide: Bool) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            // Centered on the point: the baseline below it for the near side, above it for the far side, which sees it
            // turned half round about the middle of its baseline. Core Graphics counts up from the bottom.
            let baseline = z + (nearSide ? halfCap : -halfCap)
            context.saveGState()
            context.translateBy(x: toPixel(x), y: CGFloat(size) - toPixel(baseline))
            if !nearSide {
                context.rotate(by: .pi)
            }
            context.textPosition = CGPoint(x: -width / 2, y: 0)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        // The columns by letter, I left out, from the left of Black's view; the rows by number from Black's side.
        for i in 0..<lines {
            let offset = Float(i) - half
            let letter = String(Go.columns[i])
            draw(letter, offset, middle, nearSide: true)
            draw(letter, offset, -middle, nearSide: false)
            let number = String(lines - i)
            draw(number, -middle, offset, nearSide: true)
            draw(number, middle, offset, nearSide: false)
        }

        guard let pixels = context.data else { return coverage }
        let bytesPerRow = context.bytesPerRow
        coverage.withUnsafeMutableBytes { target in
            for row in 0..<size {
                (target.baseAddress! + row * size).copyMemory(from: pixels + row * bytesPerRow, byteCount: size)
            }
        }
        return coverage
    }
}
