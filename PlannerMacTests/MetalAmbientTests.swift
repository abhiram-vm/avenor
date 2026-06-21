import XCTest
import simd
@testable import PlannerMac

final class MetalAmbientTests: XCTestCase {

    // Constraint: particle buffer ≤ 256 KB at max count.
    func test_particleBuffer_withinByteBudget() {
        let bytes = MemoryLayout<Particle>.stride * ParticleConstants.maxCount
        XCTAssertLessThanOrEqual(bytes, 256 * 1024, "particle buffer exceeds 256KB")
    }

    // Default count is the spec default, and never above the hard cap.
    func test_particleCount_defaultAndCap() {
        XCTAssertEqual(ParticleConstants.count, 1000)
        XCTAssertLessThanOrEqual(ParticleConstants.count, ParticleConstants.maxCount)
        XCTAssertLessThanOrEqual(ParticleConstants.maxCount, 1200)
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
