import MetalKit

final class MetalOrbView: MTKView, MTKViewDelegate {
    private var renderer: OrbRenderer?
    private let startTime = CACurrentMediaTime()
    private var fadeStart: CFTimeInterval?
    private var fadeDuration: Double = 1.0
    var reduceMotion: Bool = false

    // Three spec orbs. base is RELATIVE (0..1) of the 280pt band; freq 0.105..0.140
    // rad/s ⇒ 45..60s per cycle. Amplitudes small → barely perceptible drift.
    private let rawOrbs: [OrbConfig] = [
        // Orb 1 — mint, center-left, r180, op0.18
        OrbConfig(base: SIMD2(0.28, 0.42), amplitude: SIMD2(40, 28),
                  freq: SIMD2(0.115, 0.131), phase: SIMD2(0.0, 1.3),
                  radius: 180, opacity: 0.18, color: OrbRenderer.mint),
        // Orb 2 — violet, center-right, r220, op0.14
        OrbConfig(base: SIMD2(0.72, 0.38), amplitude: SIMD2(36, 30),
                  freq: SIMD2(0.105, 0.122), phase: SIMD2(2.1, 0.5),
                  radius: 220, opacity: 0.14, color: OrbRenderer.violet),
        // Orb 3 — mint, bottom-center, r150, op0.12
        OrbConfig(base: SIMD2(0.50, 0.80), amplitude: SIMD2(30, 24),
                  freq: SIMD2(0.122, 0.110), phase: SIMD2(3.4, 2.6),
                  radius: 150, opacity: 0.12, color: OrbRenderer.mint),
    ]

    init() {
        let dev = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: dev)
        guard let dev,
              let r = OrbRenderer(device: dev, orbs: resolve(rawOrbs, to: bounds.size))
        else { isPaused = true; return }
        renderer = r
        delegate = self
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 30
        framebufferOnly = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private func resolve(_ orbs: [OrbConfig], to size: CGSize) -> [OrbConfig] {
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        return orbs.map { o in
            var c = o
            c.base = SIMD2<Float>(o.base.x * w, o.base.y * h)
            return c
        }
    }

    func fadeIn(duration: Double) {
        fadeDuration = duration
        fadeStart = CACurrentMediaTime()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if let dev = device {
            renderer = OrbRenderer(device: dev, orbs: resolve(rawOrbs, to: size))
            renderer?.resize(to: size)
        }
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let globalOpacity: Float
        if reduceMotion {
            globalOpacity = 1                    // static: no fade, no movement
        } else if let fs = fadeStart {
            let x = Float(min((now - fs) / max(fadeDuration, 0.0001), 1.0))
            globalOpacity = 1 - (1 - x) * (1 - x)   // easeOutQuad
        } else {
            globalOpacity = 1
        }
        let elapsed = Float(now - startTime)
        renderer?.draw(in: view, elapsedTime: elapsed,
                       globalOpacity: globalOpacity, reduceMotion: reduceMotion)
    }
}
