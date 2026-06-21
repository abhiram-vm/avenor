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
