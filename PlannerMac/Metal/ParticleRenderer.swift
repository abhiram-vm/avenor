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

// ParticleRenderer class is implemented in Task 3.
