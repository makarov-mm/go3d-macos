import AppKit
import CoreText
import Metal

/// A font drawn by Core Text into a texture of coverage, glyph by glyph, with the Latin and Cyrillic letters and the
/// symbols the interface uses; text is measured and laid out from it.
@MainActor
final class FontAtlas {
    struct Glyph {
        var u0: Float = 0, v0: Float = 0, u1: Float = 0, v1: Float = 0 // in the atlas
        var width: Float = 0, height: Float = 0                         // of the quad, in pixels
        var left: Float = 0, top: Float = 0                             // from the pen and the line's top to the quad
        var advance: Float = 0
    }

    let lineHeight: Float
    let ascent: Float
    let texture: any MTLTexture
    private var glyphs: [UInt32: Glyph] = [:]
    private var fallback = Glyph()

    /// The characters in the atlas: ASCII, the Russian alphabet, and the punctuation, arrows and key symbols of the
    /// interface.
    private static let characters: [UInt32] = Array(0x20..<0x7F) + Array(0x410...0x44F) + [
        0x401, 0x451, 0x2014, 0x2013, 0x2026, 0x2022, 0x00B7, 0x2190, 0x2192, 0x2191, 0x2193, 0x00D7, 0x00BD, 0x00AB, 0x00BB, 0x2116,
        0x00A9, 0x2318, 0x21E7, 0x2303, 0x2325, 0x232B, 0x21A9, 0x238B, 0x25B2, 0x25BC, 0x25C0, 0x25B6,
    ]

    /// A font of the given pixel size, from the system's.
    init(device: any MTLDevice, pixelSize: CGFloat, weight: NSFont.Weight) throws {
        let font = NSFont.systemFont(ofSize: max(6, pixelSize.rounded()), weight: weight) as CTFont
        let fontAscent = CTFontGetAscent(font), fontDescent = CTFontGetDescent(font), leading = CTFontGetLeading(font)
        lineHeight = Float((fontAscent + fontDescent + leading).rounded(.up))
        ascent = Float(fontAscent.rounded())

        struct Item {
            var character: UInt32
            var line: CTLine
            var advance: CGFloat
            var x = 0, y = 0
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        var items: [Item] = []
        for character in Self.characters {
            guard let scalar = Unicode.Scalar(character) else { continue }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(Character(scalar)), attributes: attributes) as CFAttributedString)
            items.append(Item(character: character, line: line, advance: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))))
        }

        // Cells in rows, with room for overhanging strokes and for symbols from fonts that reach further.
        let pad = max(2, Int(pixelSize) / 6)
        let ascentPixels = Int(fontAscent.rounded(.up)), descentPixels = Int(fontDescent.rounded(.up))
        let cellHeight = ascentPixels + descentPixels + 2 * pad
        var atlasWidth = 256, atlasHeight = 0
        while true {
            var x = 0, y = 0
            for index in items.indices {
                let cellWidth = Int(items[index].advance.rounded(.up)) + 2 * pad
                if x + cellWidth > atlasWidth {
                    x = 0
                    y += cellHeight
                }
                items[index].x = x
                items[index].y = y
                x += cellWidth
            }
            atlasHeight = y + cellHeight
            if atlasHeight <= atlasWidth {
                break
            }
            atlasWidth *= 2
        }

        guard let context = CGContext(data: nil, width: atlasWidth, height: atlasHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw RenderError("There is no room to draw the font.")
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.setAllowsFontSmoothing(false)
        for item in items {
            // Core Graphics counts up from the bottom; the atlas's rows run down from the top.
            context.textPosition = CGPoint(x: CGFloat(item.x + pad), y: CGFloat(atlasHeight - (item.y + pad + ascentPixels)))
            CTLineDraw(item.line, context)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: atlasWidth, height: atlasHeight, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor), let pixels = context.data else {
            throw RenderError("The font's texture cannot be made.")
        }
        texture.replace(region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight), mipmapLevel: 0, withBytes: pixels, bytesPerRow: context.bytesPerRow)
        self.texture = texture

        let w = Float(atlasWidth), h = Float(atlasHeight)
        for item in items {
            let cellWidth = Int(item.advance.rounded(.up)) + 2 * pad
            glyphs[item.character] = Glyph(u0: Float(item.x) / w, v0: Float(item.y) / h, u1: Float(item.x + cellWidth) / w,
                                           v1: Float(item.y + cellHeight) / h, width: Float(cellWidth), height: Float(cellHeight),
                                           left: Float(-pad), top: Float(-pad), advance: Float(item.advance))
        }
        fallback = glyphs[UInt32(UInt8(ascii: "?"))] ?? Glyph()
    }

    func glyph(_ character: Unicode.Scalar) -> Glyph { glyphs[character.value] ?? fallback }

    func measure(_ text: String) -> Float {
        text.unicodeScalars.reduce(0) { $0 + glyph($1).advance }
    }
}
