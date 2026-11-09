import Metal

/// The shaders compiled from their source when the game starts, and the pipeline states made from them.
@MainActor
final class ShaderLibrary {
    enum Blending {
        case none
        /// Over what is there, by the source's alpha.
        case alpha
        /// Added onto what is there.
        case additive
        /// Over what is there, the alpha kept for the window.
        case interface
    }

    let device: any MTLDevice
    private let library: any MTLLibrary

    init(device: any MTLDevice) throws {
        self.device = device
        do {
            library = try device.makeLibrary(source: ShaderSource.all, options: nil)
        } catch {
            throw RenderError("The shaders do not compile:\n\(error.localizedDescription)")
        }
    }

    func function(_ name: String) throws -> any MTLFunction {
        guard let function = library.makeFunction(name: name) else { throw RenderError("The shader function \(name) is missing.") }
        return function
    }

    func renderPipeline(_ label: String, vertex: String, fragment: String?, color: MTLPixelFormat?, depth: MTLPixelFormat = .invalid,
                        samples: Int = 1, blending: Blending = .none) throws -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = try function(vertex)
        descriptor.fragmentFunction = try fragment.map { try function($0) }
        descriptor.rasterSampleCount = samples
        descriptor.depthAttachmentPixelFormat = depth
        if let color {
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = color
            switch blending {
            case .none:
                break
            case .alpha:
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .sourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .additive:
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .one
            case .interface:
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RenderError("The \(label) pipeline cannot be made:\n\(error.localizedDescription)")
        }
    }

    func computePipeline(_ name: String) throws -> any MTLComputePipelineState {
        do {
            return try device.makeComputePipelineState(function: try function(name))
        } catch {
            throw RenderError("The \(name) kernel cannot be made:\n\(error.localizedDescription)")
        }
    }

    func depthState(_ compare: MTLCompareFunction, write: Bool) -> (any MTLDepthStencilState)? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        return device.makeDepthStencilState(descriptor: descriptor)
    }
}

struct RenderError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
