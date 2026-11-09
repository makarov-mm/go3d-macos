import Metal

/// A mesh in GPU buffers: vertices read by their index in the shaders, and 32-bit indices.
struct GpuMesh {
    let vertices: any MTLBuffer
    let indices: any MTLBuffer
    let count: Int

    init?<Vertex>(device: any MTLDevice, vertices: [Vertex], indices: [UInt32]) {
        guard !indices.isEmpty,
              let vertexBuffer = vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
              let indexBuffer = indices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }
        self.vertices = vertexBuffer
        self.indices = indexBuffer
        count = indices.count
    }

    init?(device: any MTLDevice, mesh: StoneMesh) {
        self.init(device: device, vertices: mesh.vertices, indices: mesh.indices)
    }

    init?(device: any MTLDevice, mesh: SurfaceMesh) {
        self.init(device: device, vertices: mesh.vertices, indices: mesh.indices)
    }

    /// Draws the mesh; its vertices go to buffer 0 of the vertex function.
    func draw(_ encoder: any MTLRenderCommandEncoder, instances: Int = 1) {
        guard instances > 0 else { return }
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: indices,
                                      indexBufferOffset: 0, instanceCount: instances)
    }
}

/// Buffers written by the CPU every frame, one for each frame the GPU may still be drawing; the game lets at most
/// `count` frames be in flight, so the buffer handed out was last read at least that many frames ago.
@MainActor
final class BufferRing {
    /// The frames that may be in flight.
    nonisolated static let count = 3

    private let device: any MTLDevice
    private var buffers: [(any MTLBuffer)?]
    private var index = 0

    init(device: any MTLDevice) {
        self.device = device
        buffers = Array(repeating: nil, count: Self.count)
    }

    /// The next buffer, of at least `length` bytes; it grows to the next power of two when it is too small.
    func next(length: Int) -> (any MTLBuffer)? {
        index = (index + 1) % buffers.count
        if let buffer = buffers[index], buffer.length >= length {
            return buffer
        }
        var capacity = 4096
        while capacity < length {
            capacity *= 2
        }
        buffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return buffers[index]
    }
}
