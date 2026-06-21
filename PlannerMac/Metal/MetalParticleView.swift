import MetalKit

final class MetalParticleView: MTKView, MTKViewDelegate {
    private var renderer: ParticleRenderer?
    private let semaphore = DispatchSemaphore(value: 3)
    private var mode: Int = 0
    private var captureResetPending = false
    var reduceMotion: Bool = false

    init() {
        let dev = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: dev)
        guard let dev, let r = ParticleRenderer(device: dev) else { isPaused = true; return }
        renderer = r
        delegate = self
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 60
        framebufferOnly = true
        r.resize(to: bounds.size)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func triggerFocus() { mode = 1 }
    func triggerIdle()  { mode = 0 }
    func triggerCapture() {
        mode = 2
        captureResetPending = true   // consumed after one drawn frame
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.resize(to: size)
    }

    func draw(in view: MTKView) {
        guard let renderer else { return }
        semaphore.wait()
        // mode 0 passes .zero so the renderer uses its computed default center;
        // focus/capture pass the live bar center (current bounds midpoint).
        let activeCenter: SIMD2<Float> = (mode == 0)
            ? .zero
            : SIMD2<Float>(Float(bounds.midX), Float(bounds.midY))
        renderer.draw(in: view, mode: mode, captureBarCenter: activeCenter,
                      reduceMotion: reduceMotion, semaphore: semaphore)
        if captureResetPending {     // capture is a one-frame impulse → back to focus
            captureResetPending = false
            mode = 1
        }
    }
}
