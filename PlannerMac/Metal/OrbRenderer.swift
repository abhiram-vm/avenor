import simd
import Metal

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
