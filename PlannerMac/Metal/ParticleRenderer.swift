import simd
import Metal

/// CPU mirror of the `Particle` struct in AvenorParticles.metal.
/// Field order and types MUST match the .metal definition exactly.
struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var size: Float
    var opacity: Float
}

/// CPU mirror of `Uniforms` in AvenorParticles.metal.
struct ParticleUniforms {
    var mode: Int32              // 0 idle, 1 focus, 2 capture
    var captureBarCenter: SIMD2<Float>
    var deltaTime: Float
    var reduceMotion: Bool
}

enum ParticleConstants {
    static let count = 1000
    static let maxCount = 1200
}

import MetalKit

final class ParticleRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState

    // Triple-buffered particle storage.
    private static let bufferCount = 3
    private var particleBuffers: [MTLBuffer] = []
    private var bufferIndex = 0

    private var bounds = SIMD2<Float>(600, 60)
    private var defaultCenter = SIMD2<Float>(300, 30)
    private var lastFrameTime = CACurrentMediaTime()

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let compute = library.makeFunction(name: "updateParticles"),
              let vfn = library.makeFunction(name: "particleVertex"),
              let ffn = library.makeFunction(name: "particleFragment")
        else { return nil }
        self.queue = queue

        do {
            computePipeline = try device.makeComputePipelineState(function: compute)
        } catch { return nil }

        let rp = MTLRenderPipelineDescriptor()
        rp.vertexFunction = vfn
        rp.fragmentFunction = ffn
        let att = rp.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one      // additive
        att.destinationRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .one
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: rp)
        } catch { return nil }

        seedBuffers()
    }

    private func seedBuffers() {
        let n = ParticleConstants.count
        var seed = [Particle]()
        seed.reserveCapacity(n)
        for _ in 0..<n {
            let r1 = Float.random(in: 0...1), r2 = Float.random(in: 0...1)
            seed.append(Particle(
                position: SIMD2<Float>(r1 * bounds.x, r2 * bounds.y),
                velocity: .zero,
                life: 1,
                size: Float.random(in: 2...4),
                opacity: Float.random(in: 0.15...0.25)))
        }
        let len = MemoryLayout<Particle>.stride * n
        particleBuffers = (0..<Self.bufferCount).compactMap {
            _ in device.makeBuffer(bytes: seed, length: len, options: .storageModeShared)
        }
    }

    func resize(to size: CGSize) {
        bounds = SIMD2<Float>(max(Float(size.width), 1), max(Float(size.height), 1))
        defaultCenter = bounds * 0.5
    }

    func draw(in view: MTKView, mode: Int, captureBarCenter: SIMD2<Float>,
              reduceMotion: Bool, semaphore: DispatchSemaphore) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer() else { semaphore.signal(); return }

        let now = CACurrentMediaTime()
        let dt = Float(now - lastFrameTime)
        lastFrameTime = now

        let center = (captureBarCenter == .zero) ? defaultCenter : captureBarCenter
        var u = ParticleUniforms(mode: Int32(mode), captureBarCenter: center,
                                 deltaTime: dt, reduceMotion: reduceMotion)
        var bnds = bounds

        bufferIndex = (bufferIndex + 1) % Self.bufferCount
        let buf = particleBuffers[bufferIndex]

        // Compute pass.
        if let ce = cmd.makeComputeCommandEncoder() {
            ce.setComputePipelineState(computePipeline)
            ce.setBuffer(buf, offset: 0, index: 0)
            ce.setBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
            ce.setBytes(&bnds, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            let w = computePipeline.maxTotalThreadsPerThreadgroup
            ce.dispatchThreads(MTLSize(width: ParticleConstants.count, height: 1, depth: 1),
                               threadsPerThreadgroup: MTLSize(width: min(w, 256), height: 1, depth: 1))
            ce.endEncoding()
        }

        // Render pass.
        if let re = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            re.setRenderPipelineState(renderPipeline)
            re.setVertexBuffer(buf, offset: 0, index: 0)
            re.setVertexBytes(&bnds, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            re.setVertexBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
            re.drawPrimitives(type: .point, vertexStart: 0, vertexCount: ParticleConstants.count)
            re.endEncoding()
        }

        cmd.addCompletedHandler { _ in semaphore.signal() }
        cmd.present(drawable)
        cmd.commit()
    }
}
