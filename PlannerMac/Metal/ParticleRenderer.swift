import simd
import MetalKit

/// One particle's GPU vertex: pixel-space position, point size (px), final opacity.
/// CPU mirror of `VertexIn` in AvenorParticles.metal — field order/types must match.
struct ParticleVertex {
    var position: SIMD2<Float>
    var size: Float
    var opacity: Float
}

enum ParticleConstants {
    static let count = 120
}

final class ParticleRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private static let bufferCount = 3
    private var vertexBuffers: [MTLBuffer] = []
    private var bufferIndex = 0

    private var size = SIMD2<Float>(400, 100)   // drawable px (set in resize)
    private var lastTime = CACurrentMediaTime()
    private var elapsed: Float = 0
    private var seeded = false

    // CPU simulation state.
    private struct P {
        var x: Float            // horizontal home (px), gaussian about centerX
        var yAbove: Float       // px above the bar (0..bandHeight), drifts up
        var drift: Float        // upward px/s (1..3)
        var wobbleAmp: Float    // horizontal wobble amplitude (px)
        var wobbleFreq: Float   // wobble rad/s
        var phase: Float        // wobble + pulse phase
        var size: Float         // 2..4
        var baseOpacity: Float  // 0.4..0.7
        var burst: SIMD2<Float> // capture displacement (px)
        var burstVel: SIMD2<Float>
    }
    private var particles: [P] = []
    private let bandHeight: Float = 80      // particles live 0..80px above the bar
    private let hSpread: Float = 100        // gaussian stddev → ~400px visible width

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "particleVertex"),
              let ffn = library.makeFunction(name: "particleFragment")
        else { return nil }
        self.queue = queue

        let rp = MTLRenderPipelineDescriptor()
        rp.vertexFunction = vfn
        rp.fragmentFunction = ffn
        let att = rp.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one        // additive
        att.destinationRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .one
        do { pipeline = try device.makeRenderPipelineState(descriptor: rp) }
        catch { return nil }

        let len = MemoryLayout<ParticleVertex>.stride * ParticleConstants.count
        vertexBuffers = (0..<Self.bufferCount).compactMap {
            _ in device.makeBuffer(length: len, options: .storageModeShared)
        }
        guard vertexBuffers.count == Self.bufferCount else { return nil }
    }

    private func gaussian() -> Float {
        // Box–Muller, one normal sample.
        let u1 = max(Float.random(in: 0...1), 1e-6), u2 = Float.random(in: 0...1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    private func seed() {
        let centerX = size.x * 0.5
        particles = (0..<ParticleConstants.count).map { _ in
            P(x: centerX + gaussian() * hSpread,
              yAbove: Float.random(in: 0...bandHeight),
              drift: Float.random(in: 1...3),
              wobbleAmp: Float.random(in: 4...8),
              wobbleFreq: Float.random(in: 0.4...0.9),
              phase: Float.random(in: 0...(2 * .pi)),
              size: Float.random(in: 2...4),
              baseOpacity: Float.random(in: 0.4...0.7),
              burst: .zero, burstVel: .zero)
        }
    }

    func resize(to s: CGSize) {
        size = SIMD2<Float>(max(Float(s.width), 1), max(Float(s.height), 1))
        // Seed once, on the first REAL drawable size (init/zero-bounds give 1x1).
        if !seeded && size.x > 1 { seed(); seeded = true }
    }

    /// Capture: kick every particle radially outward from the bar's bottom-center.
    func burst() {
        let origin = SIMD2<Float>(size.x * 0.5, size.y)   // bar top-center, in view px
        for i in particles.indices {
            let pos = currentPos(particles[i], wobbleX: 0)
            var dir = pos - origin
            let len = simd_length(dir)
            dir = len > 1e-4 ? dir / len : SIMD2<Float>(0, -1)
            particles[i].burstVel += dir * Float.random(in: 270...540)  // px/s impulse; spring+damping yields ~40..80px peak displacement
        }
    }

    // Home position (no burst), optionally with wobble already applied.
    private func currentPos(_ p: P, wobbleX: Float) -> SIMD2<Float> {
        SIMD2<Float>(p.x + wobbleX, size.y - p.yAbove)   // yAbove=0 → bar top (view bottom)
    }

    func draw(in view: MTKView, mode: Int, reduceMotion: Bool, semaphore: DispatchSemaphore) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer() else { semaphore.signal(); return }

        // Nothing to draw until the first real drawable size has seeded the field;
        // never render 120 verts from an unwritten buffer. Keep the semaphore balanced.
        guard !particles.isEmpty else { semaphore.signal(); return }

        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTime, 1.0 / 20.0))   // clamp first/long frames
        lastTime = now
        if !reduceMotion { elapsed += dt }

        bufferIndex = (bufferIndex + 1) % Self.bufferCount
        let buf = vertexBuffers[bufferIndex]
        let out = buf.contents().bindMemory(to: ParticleVertex.self,
                                            capacity: ParticleConstants.count)

        for i in particles.indices {
            var p = particles[i]
            var wobbleX: Float = 0
            var opacity = p.baseOpacity

            if !reduceMotion {
                // Idle drift upward + respawn at the bottom with a fresh gaussian x.
                p.yAbove += p.drift * dt
                if p.yAbove > bandHeight {
                    p.yAbove -= bandHeight
                    p.x = size.x * 0.5 + gaussian() * hSpread
                }
                wobbleX = p.wobbleAmp * sin(p.wobbleFreq * elapsed + p.phase)

                // Focus (mode 1): pulse opacity 0.4↔0.7 over a 2s cycle, phase-offset.
                if mode == 1 {
                    let s = 0.5 + 0.5 * sin((2 * .pi / 2.0) * elapsed + p.phase)
                    opacity = 0.4 + 0.3 * s
                }

                // Capture spring: integrate burst offset back toward 0 (~1s settle).
                p.burstVel += -45.0 * p.burst * dt          // spring toward home
                p.burstVel *= exp(-6.0 * dt)                // damping
                p.burst += p.burstVel * dt
            }

            particles[i] = p
            let pos = currentPos(p, wobbleX: wobbleX) + (reduceMotion ? .zero : p.burst)
            out[i] = ParticleVertex(position: pos, size: p.size, opacity: opacity)
        }

        var ds = size
        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&ds, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: ParticleConstants.count)
            enc.endEncoding()
        }
        cmd.addCompletedHandler { _ in semaphore.signal() }
        cmd.present(drawable)
        cmd.commit()
    }
}
