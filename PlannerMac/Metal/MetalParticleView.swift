import MetalKit

final class MetalParticleView: MTKView, MTKViewDelegate {
    private var renderer: ParticleRenderer?
    private let semaphore = DispatchSemaphore(value: 3)
    private var mode: Int = 0            // 0 idle, 1 focus
    private var capturePending = false
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
    func triggerCapture() { capturePending = true }   // applied once on next frame

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.resize(to: size)
    }

    func draw(in view: MTKView) {
        guard let renderer else { return }
        if capturePending { capturePending = false; renderer.burst() }
        semaphore.wait()
        renderer.draw(in: view, mode: mode, reduceMotion: reduceMotion, semaphore: semaphore)
    }
}
