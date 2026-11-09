import Metal

/// Draws the scene: shadows, reflections, the lit scene in high dynamic range with multisampling, then bloom and tone
/// mapping into the window, with the interface drawn on top by the caller.
///
/// A frame is encoded in two steps, so that the interface can be laid out in between, as the game reacts to clicks
/// while it draws it: `encodeScene` for everything up to the bloom, and `encodeComposite` for the final image.
@MainActor
final class Renderer {
    static let colorFormat = MTLPixelFormat.rgba16Float
    static let depthFormat = MTLPixelFormat.depth32Float
    static let drawableFormat = MTLPixelFormat.bgra8Unorm

    private static let shadowSize = 2048
    private static let environmentSize = 512
    private static let irradianceSize = 32
    private static let prefilteredSize = 256
    private static let prefilteredLevels = 6
    private static let brdfSize = 128
    private static let labelSize = 4096
    private static let tableRadius: Float = 90
    private static let bloomLevels = 6
    private static let sampleCount = 4

    /// A run of stones in the instance buffer drawn with one call.
    private struct StoneRange {
        var first = 0, count = 0
        var white = false
    }

    /// The pictures of the size of the window.
    private struct ScreenTargets {
        let sceneColor: any MTLTexture // multisampled
        let sceneDepth: any MTLTexture
        let resolved: any MTLTexture
        let reflectionColor: any MTLTexture // half size, blurred into its mip levels
        let reflectionDepth: any MTLTexture
        let bloom: [any MTLTexture]
    }

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    private let shaders: ShaderLibrary

    private let stonePipeline, stoneBlendPipeline, stoneReflectionPipeline, surfacePipeline, backgroundPipeline: any MTLRenderPipelineState
    private let shadowSurfacePipeline, shadowStonePipeline: any MTLRenderPipelineState
    private let resolvePipeline, bloomDownPipeline, bloomUpPipeline, compositePipeline: any MTLRenderPipelineState
    private let environmentKernel, irradianceKernel, prefilterKernel, brdfKernel: any MTLComputePipelineState
    private let depthWrite, depthTestOnly, depthBackground: any MTLDepthStencilState

    private let stone: GpuMesh, simpleStone: GpuMesh
    private var boardTop, boardSides, table, bowl, lid: GpuMesh?
    private let instanceBuffers: BufferRing
    private var instanceBuffer: (any MTLBuffer)?
    private var opaque: [StoneRange] = []
    private var translucent: [StoneRange] = [] // one at a time, the furthest first

    private let shadowMap: any MTLTexture
    private let environment, irradiance, prefiltered, brdf: any MTLTexture
    private let prefilteredViews: [any MTLTexture]
    private var labels: (any MTLTexture)?
    private var targets: ScreenTargets?

    private var theme = Themes.at(0)
    private var layout = BoardLayout(size: 19)
    private var lightViewProjection = Mat4.identity
    private var shadowRadius: Float = 10, shadowRange: Float = 30
    private var frame = FrameData()

    private(set) var width = 0, height = 0

    init(shaders: ShaderLibrary, stoneShape: (detailed: StoneMesh, simple: StoneMesh)) throws {
        self.shaders = shaders
        device = shaders.device
        guard let queue = device.makeCommandQueue() else { throw RenderError("The GPU has no command queue.") }
        self.queue = queue

        let color = Self.colorFormat, depth = Self.depthFormat, samples = Self.sampleCount
        stonePipeline = try shaders.renderPipeline("stones", vertex: "stoneVertex", fragment: "stoneFragment", color: color, depth: depth, samples: samples)
        stoneBlendPipeline = try shaders.renderPipeline("stones seen through", vertex: "stoneVertex", fragment: "stoneFragment", color: color, depth: depth,
                                                        samples: samples, blending: .alpha)
        stoneReflectionPipeline = try shaders.renderPipeline("reflected stones", vertex: "stoneVertex", fragment: "stoneFragment", color: color, depth: depth)
        surfacePipeline = try shaders.renderPipeline("surfaces", vertex: "surfaceVertex", fragment: "surfaceFragment", color: color, depth: depth, samples: samples)
        backgroundPipeline = try shaders.renderPipeline("background", vertex: "fullscreenVertex", fragment: "backgroundFragment", color: color, depth: depth,
                                                        samples: samples)
        shadowSurfacePipeline = try shaders.renderPipeline("shadow of the surfaces", vertex: "shadowSurfaceVertex", fragment: nil, color: nil, depth: depth)
        shadowStonePipeline = try shaders.renderPipeline("shadow of the stones", vertex: "shadowStoneVertex", fragment: "shadowStoneFragment", color: nil,
                                                         depth: depth)
        resolvePipeline = try shaders.renderPipeline("resolve", vertex: "fullscreenVertex", fragment: "resolveFragment", color: color)
        bloomDownPipeline = try shaders.renderPipeline("bloom down", vertex: "fullscreenVertex", fragment: "bloomDownFragment", color: color)
        bloomUpPipeline = try shaders.renderPipeline("bloom up", vertex: "fullscreenVertex", fragment: "bloomUpFragment", color: color, blending: .additive)
        compositePipeline = try shaders.renderPipeline("composite", vertex: "fullscreenVertex", fragment: "compositeFragment", color: Self.drawableFormat)
        environmentKernel = try shaders.computePipeline("environmentKernel")
        irradianceKernel = try shaders.computePipeline("irradianceKernel")
        prefilterKernel = try shaders.computePipeline("prefilterKernel")
        brdfKernel = try shaders.computePipeline("brdfKernel")
        guard let depthWrite = shaders.depthState(.less, write: true), let depthTestOnly = shaders.depthState(.less, write: false),
              let depthBackground = shaders.depthState(.lessEqual, write: false) else { throw RenderError("The depth states cannot be made.") }
        self.depthWrite = depthWrite
        self.depthTestOnly = depthTestOnly
        self.depthBackground = depthBackground

        guard let stone = GpuMesh(device: device, mesh: stoneShape.detailed), let simpleStone = GpuMesh(device: device, mesh: stoneShape.simple) else {
            throw RenderError("The stone cannot be uploaded.")
        }
        self.stone = stone
        self.simpleStone = simpleStone
        instanceBuffers = BufferRing(device: device)

        // The shadow map, read both with comparison (for filtering) and without (to find the casters).
        shadowMap = try Self.makeTexture(device, Self.depthFormat, Self.shadowSize, Self.shadowSize, usage: [.renderTarget, .shaderRead])

        environment = try Self.makeCube(device, size: Self.environmentSize, levels: Self.levels(for: Self.environmentSize))
        irradiance = try Self.makeCube(device, size: Self.irradianceSize, levels: 1)
        prefiltered = try Self.makeCube(device, size: Self.prefilteredSize, levels: Self.prefilteredLevels)
        prefilteredViews = try (0..<Self.prefilteredLevels).map { level in
            guard let view = prefiltered.makeTextureView(pixelFormat: .rgba16Float, textureType: .typeCube, levels: level..<level + 1, slices: 0..<6) else {
                throw RenderError("The light probe's levels cannot be viewed.")
            }
            return view
        }
        brdf = try Self.makeTexture(device, .rg16Float, Self.brdfSize, Self.brdfSize, usage: [.shaderRead, .shaderWrite])
        bakeBrdf()
    }

    // MARK: Setup

    func setTheme(_ newTheme: Theme) {
        theme = newTheme
        updateLightView()
        bakeEnvironment()
    }

    /// The board, the bowls and the lids for a size of board; to be set before the first frame.
    func setLayout(_ newLayout: BoardLayout) {
        layout = newLayout
        boardTop = GpuMesh(device: device, mesh: BoardGeometry.boardTop(layout))
        boardSides = GpuMesh(device: device, mesh: BoardGeometry.boardSides(layout))
        table = GpuMesh(device: device, mesh: BoardGeometry.table(radius: Self.tableRadius, height: layout.tableHeight))
        bowl = GpuMesh(device: device, mesh: BoardGeometry.bowl(radius: layout.bowlRadius, height: layout.bowlHeight))
        lid = GpuMesh(device: device, mesh: BoardGeometry.lid(radius: layout.bowlRadius))

        // The coordinates written round the lines.
        let size = Self.labelSize
        let coverage = BoardLabels.render(size: size, lines: layout.size, half: layout.half, boardHalf: layout.boardHalf)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: size, height: size, mipmapped: true)
        descriptor.usage = [.shaderRead, .renderTarget]
        if let texture = device.makeTexture(descriptor: descriptor) {
            coverage.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: size)
            }
            if let commandBuffer = queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.generateMipmaps(for: texture)
                blit.endEncoding()
                commandBuffer.commit()
            }
            labels = texture
        }
        updateLightView()
    }

    func resize(width newWidth: Int, height newHeight: Int) throws {
        let newWidth = max(newWidth, 1), newHeight = max(newHeight, 1)
        guard newWidth != width || newHeight != height || targets == nil else { return }
        width = newWidth
        height = newHeight
        targets = try makeScreenTargets()
    }

    // MARK: The frame

    /// The shadow map, the reflections, the main pass and the bloom.
    func encodeScene(_ scene: RenderScene, into commandBuffer: any MTLCommandBuffer) {
        guard let targets else { return }
        updateFrameData(scene)
        uploadStones(scene)
        encodeShadowMap(commandBuffer)
        encodeReflections(scene, targets, commandBuffer)
        encodeMainPass(scene, targets, commandBuffer)
        encodeBloom(targets, commandBuffer)
    }

    /// The final image into `target`, the window's drawable, then whatever `overlay` draws over it.
    func encodeComposite(_ scene: RenderScene, into commandBuffer: any MTLCommandBuffer, target: any MTLTexture,
                         overlay: (any MTLRenderCommandEncoder) -> Void) {
        guard let targets else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Composite"
        var params = CompositeParams()
        params.settings = Vec4(theme.exposure, theme.bloom, theme.vignette, Float(min(scene.panels.count, 4)))
        params.viewport = frame.viewport
        var panels = [Vec4](repeating: .zero, count: 4), styles = [Vec4](repeating: .zero, count: 4)
        for (i, panel) in scene.panels.prefix(4).enumerated() {
            panels[i] = Vec4(panel.x + panel.width / 2, panel.y + panel.height / 2, panel.width / 2, panel.height / 2)
            styles[i] = Vec4(panel.radius, panel.opacity, 0, 0)
        }
        params.panels = (panels[0], panels[1], panels[2], panels[3])
        params.panelStyles = (styles[0], styles[1], styles[2], styles[3])
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<CompositeParams>.stride, index: 0)
        encoder.setFragmentTexture(targets.resolved, index: 0)
        encoder.setFragmentTexture(targets.bloom[0], index: 1)
        encoder.setFragmentTexture(targets.bloom[2], index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        overlay(encoder)
        encoder.endEncoding()
    }

    private func updateFrameData(_ scene: RenderScene) {
        frame.viewProjection = scene.projection * scene.view
        frame.inverseViewProjection = frame.viewProjection.inverse
        frame.lightViewProjection = lightViewProjection
        frame.cameraPosition = scene.eye.extended(scene.time)
        frame.lightDirection = theme.keyDirection.normalized.extended(2 * shadowRadius / Float(Self.shadowSize))
        frame.lightColor = theme.keyRadiance.extended(theme.keySoftness)
        // The depth bias, the same in world units for every size of board; the fog begins beyond the board.
        let fogStart = scene.eye.length + layout.extent * 0.8
        frame.shadowParams = Vec4(shadowRange, 0.012 / shadowRange, fogStart, 0)
        frame.viewport = Vec4(Float(width), Float(height), 1 / Float(width), 1 / Float(height))
        frame.environment = Vec4(theme.diffuseLight, theme.reflectedLight, Float(Self.prefilteredLevels - 1), theme.background)
        frame.accent = theme.accent.color4
        frame.accentWarm = theme.accentWarm.color4
        frame.fog = theme.fog.extended(0.05)
    }

    /// The stones into the instance buffer: Black's opaque stones, White's, then those seen through, the furthest
    /// first, to be drawn one at a time.
    private func uploadStones(_ scene: RenderScene) {
        var instances: [StoneInstance] = []
        instances.reserveCapacity(scene.stones.count)
        func add(_ stone: StoneDraw) {
            instances.append(StoneInstance(model: stone.model, glow: stone.glowColor.extended(stone.glow),
                                           params: Vec4(stone.dissolve, stone.seed, stone.ground, stone.mark), extra: Vec4(stone.opacity, 0, 0, 0)))
        }
        opaque.removeAll()
        translucent.removeAll()
        for white in [false, true] {
            let first = instances.count
            for stone in scene.stones where stone.white == white && stone.opacity >= 1 {
                add(stone)
            }
            opaque.append(StoneRange(first: first, count: instances.count - first, white: white))
        }
        func distance(_ stone: StoneDraw) -> Float { (stone.model.transformPoint(.zero) - scene.eye).length }
        for stone in scene.stones.filter({ $0.opacity < 1 }).sorted(by: { distance($0) > distance($1) }) {
            translucent.append(StoneRange(first: instances.count, count: 1, white: stone.white))
            add(stone)
        }
        let length = max(instances.count, 1) * MemoryLayout<StoneInstance>.stride
        instanceBuffer = instanceBuffers.next(length: length)
        if let instanceBuffer, !instances.isEmpty {
            instances.withUnsafeBytes { instanceBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
    }

    private func passData(eye: Vec3, shadows: Bool, mirror: Bool) -> PassData {
        PassData(eye: eye.extended(shadows ? 0 : 1), mirror: Vec4(0, mirror ? 1 : 0, layout.boardHalf, 0))
    }

    /// The textures the shading reads: the shadow map and the light probes for every pass, and for the board the
    /// reflections and the coordinates.
    private func bindLighting(_ encoder: any MTLRenderCommandEncoder, reflections: (any MTLTexture)? = nil) {
        encoder.setFragmentTexture(shadowMap, index: 0)
        encoder.setFragmentTexture(irradiance, index: 1)
        encoder.setFragmentTexture(prefiltered, index: 2)
        encoder.setFragmentTexture(brdf, index: 3)
        if let reflections, let labels {
            encoder.setFragmentTexture(reflections, index: 4)
            encoder.setFragmentTexture(labels, index: 5)
        }
    }

    private func encodeShadowMap(_ commandBuffer: any MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Shadow map"
        encoder.setDepthStencilState(depthWrite)
        encoder.setCullMode(.none)
        encoder.setDepthBias(3, slopeScale: 1.5, clamp: 0)
        encoder.setRenderPipelineState(shadowSurfacePipeline)
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameData>.stride, index: 2)
        var draw = SurfaceDraw()
        encoder.setVertexBytes(&draw, length: MemoryLayout<SurfaceDraw>.stride, index: 1)
        boardSides?.draw(encoder)
        boardTop?.draw(encoder)
        drawBowls(encoder, material: false)
        // The opaque stones lie together at the start of the buffer.
        if let instanceBuffer {
            encoder.setRenderPipelineState(shadowStonePipeline)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
            simpleStone.draw(encoder, instances: opaque.reduce(0) { $0 + $1.count })
        }
        encoder.endEncoding()
    }

    private func encodeReflections(_ scene: RenderScene, _ targets: ScreenTargets, _ commandBuffer: any MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.reflectionColor
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = targets.reflectionDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Reflections"
        if theme.reflection > 0 {
            // The stones turned upside down under the board, seen from the camera, as if from below the board.
            var data = passData(eye: Vec3(scene.eye.x, -scene.eye.y, scene.eye.z), shadows: false, mirror: true)
            encoder.setDepthStencilState(depthWrite)
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.clockwise) // mirroring turns the winding round
            encoder.setRenderPipelineState(stoneReflectionPipeline)
            encoder.setVertexBytes(&frame, length: MemoryLayout<FrameData>.stride, index: 2)
            encoder.setVertexBytes(&data, length: MemoryLayout<PassData>.stride, index: 3)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameData>.stride, index: 0)
            encoder.setFragmentBytes(&data, length: MemoryLayout<PassData>.stride, index: 1)
            bindLighting(encoder)
            drawStones(encoder, opaque, detailed: false)
        }
        encoder.endEncoding()
        if theme.reflection > 0, let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: targets.reflectionColor)
            blit.endEncoding()
        }
    }

    private func encodeMainPass(_ scene: RenderScene, _ targets: ScreenTargets, _ commandBuffer: any MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.sceneColor
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(Double(theme.fog.x), Double(theme.fog.y), Double(theme.fog.z), 1)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = targets.sceneDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Scene"
        var data = passData(eye: scene.eye, shadows: true, mirror: false)
        encoder.setDepthStencilState(depthWrite)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameData>.stride, index: 2)
        encoder.setVertexBytes(&data, length: MemoryLayout<PassData>.stride, index: 3)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameData>.stride, index: 0)
        encoder.setFragmentBytes(&data, length: MemoryLayout<PassData>.stride, index: 1)
        bindLighting(encoder, reflections: targets.reflectionColor)

        var material = surfaceMaterial(scene)
        var marks = scene.marks
        encoder.setRenderPipelineState(surfacePipeline)
        encoder.setFragmentBytes(&material, length: MemoryLayout<SurfaceMaterial>.stride, index: 2)
        encoder.setFragmentBytes(&marks, length: marks.count, index: 4)
        drawSurface(encoder, table, kind: 2)
        drawSurface(encoder, boardSides, kind: 1)
        drawSurface(encoder, boardTop, kind: 0)
        drawBowls(encoder, material: true)

        encoder.setRenderPipelineState(stonePipeline)
        drawStones(encoder, opaque, detailed: true)

        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setDepthStencilState(depthBackground)
        encoder.setCullMode(.none)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // The stones seen through, blended over the rest.
        if !translucent.isEmpty {
            encoder.setRenderPipelineState(stoneBlendPipeline)
            encoder.setDepthStencilState(depthTestOnly)
            encoder.setCullMode(.back)
            drawStones(encoder, translucent, detailed: true)
        }
        encoder.endEncoding()
    }

    private func surfaceMaterial(_ scene: RenderScene) -> SurfaceMaterial {
        let t = theme, l = layout
        var m = SurfaceMaterial()
        m.boardColor = t.boardColor.color4
        m.boardSurface = Vec4(t.boardRoughness, t.boardClearcoat, t.boardClearcoatRoughness, t.boardPattern)
        m.boardReflection = Vec4(t.reflection, t.reflectionBlur, 0, 0)
        m.gridColor = t.gridColor.color4
        m.grid = Vec4(t.gridWidth, t.gridMetallic, t.gridRoughness, t.gridGlow)
        m.boardShape = Vec4(Float(l.size), l.half, l.boardHalf, t.starRadius)
        m.bowlColor = t.bowlColor.color4
        m.bowlSurface = Vec4(t.bowlRoughness, t.bowlClearcoat, t.bowlPattern, t.bowlSeed)
        m.tableColor = t.tableColor.color4
        m.tableSurface = Vec4(t.tableRoughness, t.tablePattern, t.tableSheen, t.tableGlow)
        m.tableFade = Vec4(l.extent + 1.5, l.extent + 14, 0, 0)
        m.markStyle = Vec4(scene.estimate ? 1 : 0, scene.coordinates ? 1 : 0, 0, 0)
        // The soft shade round the feet of the bowls and the lids.
        m.discs = (Vec4(l.bowls[0].x, l.bowls[0].z, l.bowlRadius * 0.68, 0.65), Vec4(l.bowls[1].x, l.bowls[1].z, l.bowlRadius * 0.68, 0.65),
                   Vec4(l.lids[0].x, l.lids[0].z, l.bowlRadius * 0.95, 0.5), Vec4(l.lids[1].x, l.lids[1].z, l.bowlRadius * 0.95, 0.5))
        return m
    }

    private func drawSurface(_ encoder: any MTLRenderCommandEncoder, _ mesh: GpuMesh?, kind: Float, model: Mat4 = .identity, bowlShape: Vec4 = .zero) {
        guard let mesh else { return }
        var draw = SurfaceDraw(model: model, bowlShape: bowlShape, kind: Vec4(kind, 0, 0, 0))
        encoder.setVertexBytes(&draw, length: MemoryLayout<SurfaceDraw>.stride, index: 1)
        encoder.setFragmentBytes(&draw, length: MemoryLayout<SurfaceDraw>.stride, index: 3)
        mesh.draw(encoder)
    }

    /// The bowls and the lids, each turned its own way so that the grain differs.
    private func drawBowls(_ encoder: any MTLRenderCommandEncoder, material: Bool) {
        for i in 0..<2 {
            let place = layout.bowls[i]
            let bowlModel = Mat4.translation(place) * Mat4.rotationY(1.3 + 2.1 * Float(i))
            let lidModel = Mat4.translation(layout.lids[i]) * Mat4.rotationY(0.4 + 2.6 * Float(i))
            if material {
                drawSurface(encoder, bowl, kind: 3, model: bowlModel, bowlShape: Vec4(place.x, place.z, place.y + layout.bowlHeight, layout.bowlRadius))
                drawSurface(encoder, lid, kind: 3, model: lidModel)
            } else {
                for (mesh, model) in [(bowl, bowlModel), (lid, lidModel)] {
                    var draw = SurfaceDraw(model: model)
                    encoder.setVertexBytes(&draw, length: MemoryLayout<SurfaceDraw>.stride, index: 1)
                    mesh?.draw(encoder)
                }
            }
        }
    }

    private func drawStones(_ encoder: any MTLRenderCommandEncoder, _ ranges: [StoneRange], detailed: Bool) {
        guard let instanceBuffer else { return }
        for range in ranges where range.count > 0 {
            var material = stoneMaterial(white: range.white)
            encoder.setFragmentBytes(&material, length: MemoryLayout<StoneMaterial>.stride, index: 2)
            encoder.setVertexBuffer(instanceBuffer, offset: range.first * MemoryLayout<StoneInstance>.stride, index: 1)
            (detailed ? stone : simpleStone).draw(encoder, instances: range.count)
        }
    }

    private func stoneMaterial(white: Bool) -> StoneMaterial {
        let look = white ? theme.white : theme.black
        return StoneMaterial(albedo: look.albedo.color4,
                             surface: Vec4(look.roughness, look.metallic, look.clearcoat, look.clearcoatRoughness),
                             style: Vec4(look.subsurface, look.patternStrength, look.pattern, white ? 0 : 1),
                             trim: look.trim.extended(look.trimStrength),
                             edge: look.edge.extended(look.edgeStrength))
    }

    /// The samples resolved, then bloom: halved down to a small image, then the levels added back up.
    private func encodeBloom(_ targets: ScreenTargets, _ commandBuffer: any MTLCommandBuffer) {
        fullscreenPass(commandBuffer, target: targets.resolved, label: "Resolve", load: false) { encoder in
            encoder.setRenderPipelineState(resolvePipeline)
            encoder.setFragmentTexture(targets.sceneColor, index: 0)
        }
        for level in 0..<Self.bloomLevels {
            let source = level == 0 ? targets.resolved : targets.bloom[level - 1]
            var params = Vec4(1 / Float(source.width), 1 / Float(source.height), level == 0 ? 1 : 0, 0)
            fullscreenPass(commandBuffer, target: targets.bloom[level], label: "Bloom down", load: false) { encoder in
                encoder.setRenderPipelineState(bloomDownPipeline)
                encoder.setFragmentBytes(&params, length: MemoryLayout<Vec4>.stride, index: 0)
                encoder.setFragmentTexture(source, index: 0)
            }
        }
        for level in stride(from: Self.bloomLevels - 2, through: 0, by: -1) {
            let source = targets.bloom[level + 1]
            var params = Vec4(1 / Float(source.width), 1 / Float(source.height), 0, 0)
            fullscreenPass(commandBuffer, target: targets.bloom[level], label: "Bloom up", load: true) { encoder in
                encoder.setRenderPipelineState(bloomUpPipeline)
                encoder.setFragmentBytes(&params, length: MemoryLayout<Vec4>.stride, index: 0)
                encoder.setFragmentTexture(source, index: 0)
            }
        }
    }

    /// A pass that draws one triangle over all of `target`, keeping what is there when `load` is set.
    private func fullscreenPass(_ commandBuffer: any MTLCommandBuffer, target: any MTLTexture, label: String, load: Bool,
                                setup: (any MTLRenderCommandEncoder) -> Void) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = load ? .load : .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = label
        setup(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: Light

    /// The key light's view: a box round everything that casts or takes a shadow.
    private func updateLightView() {
        var radius = layout.boardHalf * 1.42
        for place in layout.bowls + layout.lids {
            radius = max(radius, Vec3(place.x, 0, place.z).length + layout.bowlRadius)
        }
        shadowRadius = radius + 0.5
        shadowRange = 2 * shadowRadius + 16

        let toLight = theme.keyDirection.normalized
        let up = abs(toLight.y) > 0.99 ? Vec3(0, 0, 1) : Vec3(0, 1, 0)
        let view = Mat4.lookAt(eye: toLight * (shadowRadius + 8), target: .zero, up: up)
        let projection = Mat4.orthographic(left: -shadowRadius, right: shadowRadius, bottom: -shadowRadius, top: shadowRadius,
                                           near: 0.5, far: 0.5 + shadowRange)
        lightViewProjection = projection * view
    }

    /// The split-sum table, once.
    private func bakeBrdf() {
        guard let commandBuffer = queue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(brdfKernel)
        encoder.setTexture(brdf, index: 0)
        Self.dispatch(encoder, size: Self.brdfSize, layers: 1)
        encoder.endEncoding()
        commandBuffer.commit()
    }

    /// The studio light of the theme, baked into the light probes.
    private func bakeEnvironment() {
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        commandBuffer.label = "Light probes"
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            var params = EnvironmentParams(ceilingColor: theme.ceiling.color4, horizonColor: theme.horizon.color4, floorColor: theme.floor.color4,
                                           counts: SIMD4<UInt32>(UInt32(min(theme.panels.count, 8)), 0, 0, 0))
            var directions = [Vec4](repeating: .zero, count: 8), shapes = directions, colors = directions
            for (i, panel) in theme.panels.prefix(8).enumerated() {
                directions[i] = panel.direction.extended(panel.roll)
                shapes[i] = Vec4(panel.halfSize.x, panel.halfSize.y, panel.corner, panel.softness)
                colors[i] = panel.radiance.extended(panel.falloff)
            }
            encoder.setComputePipelineState(environmentKernel)
            encoder.setTexture(environment, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<EnvironmentParams>.stride, index: 0)
            encoder.setBytes(directions, length: directions.count * MemoryLayout<Vec4>.stride, index: 1)
            encoder.setBytes(shapes, length: shapes.count * MemoryLayout<Vec4>.stride, index: 2)
            encoder.setBytes(colors, length: colors.count * MemoryLayout<Vec4>.stride, index: 3)
            Self.dispatch(encoder, size: Self.environmentSize, layers: 6)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: environment)
            blit.endEncoding()
        }
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            var sourceLevel = Vec4(4, 0, 0, 0)
            encoder.setComputePipelineState(irradianceKernel)
            encoder.setTexture(environment, index: 0)
            encoder.setTexture(irradiance, index: 1)
            encoder.setBytes(&sourceLevel, length: MemoryLayout<Vec4>.stride, index: 0)
            Self.dispatch(encoder, size: Self.irradianceSize, layers: 6)

            encoder.setComputePipelineState(prefilterKernel)
            for (level, view) in prefilteredViews.enumerated() {
                var params = Vec4(Float(level) / Float(Self.prefilteredLevels - 1), Float(Self.environmentSize), 0, 0)
                encoder.setTexture(environment, index: 0)
                encoder.setTexture(view, index: 1)
                encoder.setBytes(&params, length: MemoryLayout<Vec4>.stride, index: 0)
                Self.dispatch(encoder, size: Self.prefilteredSize >> level, layers: 6)
            }
            encoder.endEncoding()
        }
        commandBuffer.commit()
    }

    // MARK: Resources

    private func makeScreenTargets() throws -> ScreenTargets {
        let sceneColor = try Self.makeTexture(device, Self.colorFormat, width, height, usage: [.renderTarget, .shaderRead], samples: Self.sampleCount)
        let sceneDepth = try Self.makeTexture(device, Self.depthFormat, width, height, usage: [.renderTarget], samples: Self.sampleCount)
        let resolved = try Self.makeTexture(device, Self.colorFormat, width, height, usage: [.renderTarget, .shaderRead])
        // The reflections at half size, blurred through their mip levels.
        let reflectionWidth = max(1, width / 2), reflectionHeight = max(1, height / 2)
        let reflectionLevels = min(5, Self.levels(for: max(reflectionWidth, reflectionHeight)))
        let reflectionColor = try Self.makeTexture(device, Self.colorFormat, reflectionWidth, reflectionHeight, usage: [.renderTarget, .shaderRead],
                                                   levels: reflectionLevels)
        let reflectionDepth = try Self.makeTexture(device, Self.depthFormat, reflectionWidth, reflectionHeight, usage: [.renderTarget])
        let bloom = try (0..<Self.bloomLevels).map { level in
            try Self.makeTexture(device, Self.colorFormat, max(1, width >> (level + 1)), max(1, height >> (level + 1)), usage: [.renderTarget, .shaderRead])
        }
        return ScreenTargets(sceneColor: sceneColor, sceneDepth: sceneDepth, resolved: resolved, reflectionColor: reflectionColor,
                             reflectionDepth: reflectionDepth, bloom: bloom)
    }

    private static func makeTexture(_ device: any MTLDevice, _ format: MTLPixelFormat, _ width: Int, _ height: Int, usage: MTLTextureUsage,
                                    samples: Int = 1, levels: Int = 1) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
        descriptor.pixelFormat = format
        descriptor.width = width
        descriptor.height = height
        descriptor.sampleCount = samples
        descriptor.mipmapLevelCount = levels
        descriptor.usage = usage
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError("A \(width)×\(height) texture cannot be made.") }
        return texture
    }

    private static func makeCube(_ device: any MTLDevice, size: Int, levels: Int) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: size, mipmapped: levels > 1)
        descriptor.mipmapLevelCount = levels
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError("A light probe cannot be made.") }
        return texture
    }

    private static func levels(for size: Int) -> Int {
        var levels = 1
        while size >> levels > 0 {
            levels += 1
        }
        return levels
    }

    private static func dispatch(_ encoder: any MTLComputeCommandEncoder, size: Int, layers: Int) {
        encoder.dispatchThreadgroups(MTLSize(width: (size + 7) / 8, height: (size + 7) / 8, depth: layers),
                                     threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }
}
