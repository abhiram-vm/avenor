import simd
import MetalKit

/// CPU mirror of `OrbUniforms` in AvenorOrbs.metal.
struct OrbUniforms {
    var center: SIMD2<Float>
    var radius: Float
    var color: SIMD4<Float>
    var opacity: Float
    var time: Float
    var globalOpacity: Float
}

/// Lissajous drift: base + amplitude * sin(freq * time + phase), per axis.
/// Pure function — the single source of truth for orb motion, tested in isolation.
func lissajousCenter(base: SIMD2<Float>,
                     amplitude: SIMD2<Float>,
                     freq: SIMD2<Float>,
                     phase: SIMD2<Float>,
                     time: Float) -> SIMD2<Float> {
    let angle = freq * time + phase
    return base + amplitude * SIMD2<Float>(sin(angle.x), sin(angle.y))
}

struct OrbConfig {
    var base: SIMD2<Float>       // relative 0..1 within the orb band
    var amplitude: SIMD2<Float>  // Lissajous amplitude (px)
    var freq: SIMD2<Float>       // rad/s — 0.105..0.140 ⇒ 45..60s cycle
    var phase: SIMD2<Float>
    var radius: Float            // px
    var opacity: Float
    var color: SIMD4<Float>
}

final class OrbRenderer {
    static let mint   = SIMD4<Float>(0.431, 0.906, 0.659, 1.0)  // #6EE7A8
    static let violet = SIMD4<Float>(0.486, 0.227, 0.929, 1.0)  // #7C3AED

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var configs: [OrbConfig]      // base in PIXELS (resolved by caller)
    private var size = SIMD2<Float>(800, 280)

    init?(device: MTLDevice, orbs: [OrbConfig]) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "orbVertex"),
              let ffn = library.makeFunction(name: "orbFragment")
        else { return nil }
        self.queue = queue
        self.configs = orbs

        let rp = MTLRenderPipelineDescriptor()
        rp.vertexFunction = vfn
        rp.fragmentFunction = ffn
        let att = rp.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one        // additive — overlap glows brighter
        att.destinationRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .one
        do { pipeline = try device.makeRenderPipelineState(descriptor: rp) }
        catch { return nil }
    }

    func resize(to s: CGSize) {
        size = SIMD2<Float>(max(Float(s.width), 1), max(Float(s.height), 1))
    }

    func draw(in view: MTKView, elapsedTime: Float, globalOpacity: Float, reduceMotion: Bool) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        var ds = size
        enc.setVertexBytes(&ds, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)

        for c in configs {
            let center = reduceMotion
                ? c.base
                : lissajousCenter(base: c.base, amplitude: c.amplitude,
                                  freq: c.freq, phase: c.phase, time: elapsedTime)
            var u = OrbUniforms(center: center, radius: c.radius, color: c.color,
                                opacity: c.opacity, time: elapsedTime,
                                globalOpacity: globalOpacity)
            enc.setFragmentBytes(&u, length: MemoryLayout<OrbUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
