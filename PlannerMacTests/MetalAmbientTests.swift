import XCTest
import simd
@testable import PlannerMac

final class MetalAmbientTests: XCTestCase {

    // New design: exactly 120 particles.
    func test_particleCount_is120() {
        XCTAssertEqual(ParticleConstants.count, 120)
    }

    // The uploaded per-particle vertex is compact (position + size + opacity).
    func test_particleVertex_layout() {
        // float2 (8) + float (4) + float (4) = 16 bytes, no padding.
        XCTAssertEqual(MemoryLayout<ParticleVertex>.stride, 16)
        let bufferBytes = MemoryLayout<ParticleVertex>.stride * ParticleConstants.count
        XCTAssertLessThanOrEqual(bufferBytes, 256 * 1024)
    }

    // Constraint: orb uniforms ≤ 4 KB for the whole (3-orb) array.
    func test_orbUniforms_withinByteBudget() {
        let bytes = MemoryLayout<OrbUniforms>.stride * 3
        XCTAssertLessThanOrEqual(bytes, 4 * 1024, "orb uniforms exceed 4KB")
    }

    // Lissajous: at t=0 with zero phase, position == base (sin 0 == 0).
    func test_lissajous_atZeroIsBase() {
        let base = SIMD2<Float>(100, 200)
        let p = lissajousCenter(base: base,
                                amplitude: SIMD2<Float>(40, 30),
                                freq: SIMD2<Float>(0.02, 0.03),
                                phase: SIMD2<Float>(0, 0),
                                time: 0)
        XCTAssertEqual(p.x, 100, accuracy: 0.0001)
        XCTAssertEqual(p.y, 200, accuracy: 0.0001)
    }

    // Lissajous: a quarter period on X (freq*time+phase == π/2) → base + amplitude.
    func test_lissajous_quarterPeriodPeaksOnX() {
        let base = SIMD2<Float>(0, 0)
        let freqX: Float = 0.02
        let time = (Float.pi / 2) / freqX
        let p = lissajousCenter(base: base,
                                amplitude: SIMD2<Float>(40, 0),
                                freq: SIMD2<Float>(freqX, 0),
                                phase: .zero,
                                time: time)
        XCTAssertEqual(p.x, 40, accuracy: 0.001)
    }
}
