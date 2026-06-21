import MetalKit

final class MetalOrbView: MTKView, MTKViewDelegate {
    private var renderer: OrbRenderer?
    private let startTime = CACurrentMediaTime()
    private var fadeStart: CFTimeInterval?
    private var fadeDuration: Double = 0.8
    private var globalOpacity: Float = 0
    var reduceMotion: Bool = false

    // 0..1 seeds, kept so resize can re-resolve to new pixel bounds.
    // base positions are RELATIVE (0..1) of the 200pt title band; freq 0.01–0.04
    // rad/s ⇒ 30–60s per traverse.
    private let rawOrbs: [OrbConfig] = [
        OrbConfig(base: SIMD2(0.22, 0.32), amplitude: SIMD2(60, 40),
                  freq: SIMD2(0.013, 0.019), phase: SIMD2(0.0, 1.1),
                  radius: 280, opacity: 0.10, color: OrbRenderer.mint),
        OrbConfig(base: SIMD2(0.78, 0.30), amplitude: SIMD2(50, 35),
                  freq: SIMD2(0.021, 0.011), phase: SIMD2(2.0, 0.4),
                  radius: 220, opacity: 0.08, color: OrbRenderer.mint),
        OrbConfig(base: SIMD2(0.50, 0.74), amplitude: SIMD2(70, 45),
                  freq: SIMD2(0.009, 0.017), phase: SIMD2(3.3, 2.7),
                  radius: 340, opacity: 0.12, color: OrbRenderer.violet),
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
        // isOpaque = false  ← omitted: NSView.isOpaque is get-only on macOS (compile error)
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
        renderer?.resize(to: size)
        if let dev = device {
            renderer = OrbRenderer(device: dev, orbs: resolve(rawOrbs, to: size))
            renderer?.resize(to: size)
        }
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if let fs = fadeStart {
            globalOpacity = Float(min((now - fs) / max(fadeDuration, 0.0001), 1.0))
        } else {
            globalOpacity = 1   // no fade requested → fully visible
        }
        let elapsed = Float(now - startTime)
        renderer?.draw(in: view, elapsedTime: elapsed,
                       globalOpacity: globalOpacity, reduceMotion: reduceMotion)
    }
}
