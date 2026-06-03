import SwiftUI

// MARK: - LivingMeshBackground
//
// A continuously drifting color field for the Liquid Glass theme. It sits
// BENEATH the `.ultraThinMaterial` cards so the frosted surfaces refract a
// living, breathing backdrop instead of a static gradient.
//
// Engine:
//   • iOS 18+ : native `MeshGradient`, a 3×3 control grid whose interior +
//     edge-midpoint points drift via sin/cos. Corners are pinned so the
//     field never tears at the screen edges.
//   • iOS 17  : graceful fallback — soft blurred color "blobs" drifting over
//     the theme's base gradient.
//
// Performance contract (locks 120Hz on ProMotion):
//   • `TimelineView(.animation)` ticks at the display refresh rate.
//   • The ONLY per-frame CPU work is a handful of `sin`/`cos` calls computed
//     OUTSIDE the GPU draw — `MeshGradient` itself is GPU-rasterized.
//   • No `.blur` is stacked on the mesh path (blur is fill-rate heavy); the
//     frosted depth comes from the material layer above, not from blurring
//     the field. The 17 fallback uses blur sparingly (4 blobs only).
//   • All motion is sin/cos-based, so it loops seamlessly with no boundary
//     discontinuity — there is no keyframe to snap back to.

struct LivingMeshBackground: View {

    /// Soft lavenders → muted teals → indigo. Tuned to read well under a
    /// translucent material without oversaturating the frosted cards.
    private static let palette: [Color] = [
        Color(red: 0.58, green: 0.50, blue: 0.86),  // lavender
        Color(red: 0.50, green: 0.46, blue: 0.84),  // violet
        Color(red: 0.42, green: 0.52, blue: 0.82),  // periwinkle
        Color(red: 0.36, green: 0.50, blue: 0.80),  // indigo
        Color(red: 0.32, green: 0.56, blue: 0.76),  // slate teal
        Color(red: 0.30, green: 0.58, blue: 0.74)   // muted teal
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            field(at: t)
        }
        .ignoresSafeArea()
        .drawingGroup()  // composite the field once per frame on the GPU
    }

    @ViewBuilder
    private func field(at t: TimeInterval) -> some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.controlPoints(t),
                colors: Self.meshColors,
                background: Self.palette[3]
            )
        } else {
            LegacyBlobField(t: t, palette: Self.palette)
        }
    }

    // MARK: - Mesh control points (iOS 18+)

    /// 3×3 grid. Corners pinned; edge-midpoints and the center drift on
    /// de-synced low frequencies so the field warps organically and never
    /// visibly repeats.
    @available(iOS 18.0, *)
    static func controlPoints(_ t: TimeInterval) -> [SIMD2<Float>] {
        // Small-amplitude wobble around a base coordinate. Frequencies are
        // intentionally incommensurate to defeat obvious periodicity.
        func wob(_ base: Float, freq: Double, amp: Float, phase: Double) -> Float {
            base + amp * Float(sin(t * freq + phase))
        }

        return [
            // Row 0 (top) — corners pinned, top-mid drifts horizontally.
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(wob(0.5, freq: 0.30, amp: 0.10, phase: 0.0), 0.0),
            SIMD2<Float>(1.0, 0.0),

            // Row 1 (middle) — edges drift vertically, center drifts on both.
            SIMD2<Float>(0.0, wob(0.5, freq: 0.27, amp: 0.10, phase: 1.2)),
            SIMD2<Float>(wob(0.5, freq: 0.24, amp: 0.13, phase: 2.0),
                         wob(0.5, freq: 0.21, amp: 0.13, phase: 0.5)),
            SIMD2<Float>(1.0, wob(0.5, freq: 0.26, amp: 0.10, phase: 3.1)),

            // Row 2 (bottom) — corners pinned, bottom-mid drifts horizontally.
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(wob(0.5, freq: 0.29, amp: 0.10, phase: 4.0), 1.0),
            SIMD2<Float>(1.0, 1.0)
        ]
    }

    /// Nine colors mapped to the 3×3 grid. Lavender anchors the top-left,
    /// teal anchors the bottom-right, indigo carries the diagonal — matching
    /// the theme's static gradient direction so the transition is invisible
    /// if the field is ever paused.
    @available(iOS 18.0, *)
    static var meshColors: [Color] {
        [
            palette[0], palette[1], palette[2],
            palette[1], palette[3], palette[4],
            palette[2], palette[4], palette[5]
        ]
    }
}

// MARK: - Legacy blob field (iOS 17 fallback)

/// Four soft color blobs drifting over the base gradient. Each blob's center
/// is a sin/cos function of time, so the motion is seamless. Blur is applied
/// once per blob (not stacked) to keep fill-rate in budget.
private struct LegacyBlobField: View {
    let t: TimeInterval
    let palette: [Color]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LinearGradient(
                    colors: [palette[0], palette[3], palette[5]],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                blob(palette[0], w: w, h: h, fx: 0.28, fy: 0.32, freq: 0.18, phase: 0.0)
                blob(palette[2], w: w, h: h, fx: 0.72, fy: 0.30, freq: 0.21, phase: 1.5)
                blob(palette[4], w: w, h: h, fx: 0.34, fy: 0.70, freq: 0.16, phase: 3.0)
                blob(palette[5], w: w, h: h, fx: 0.70, fy: 0.74, freq: 0.23, phase: 4.5)
            }
        }
    }

    private func blob(_ color: Color, w: CGFloat, h: CGFloat,
                      fx: CGFloat, fy: CGFloat,
                      freq: Double, phase: Double) -> some View {
        let dx = CGFloat(sin(t * freq + phase)) * w * 0.12
        let dy = CGFloat(cos(t * freq * 0.9 + phase)) * h * 0.12
        let diameter = max(w, h) * 0.7

        return Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .position(x: w * fx + dx, y: h * fy + dy)
            .blur(radius: 80)
            .opacity(0.55)
    }
}

// MARK: - Convenience modifier

extension View {
    /// Installs the Living Mesh field as a full-bleed background, but only
    /// for the Liquid Glass theme. For every other palette this defers to the
    /// standard `themedCanvas`, so call sites stay theme-agnostic:
    ///
    ///     ScrollView { ... }
    ///         .livingCanvas(palette)
    @ViewBuilder
    func livingCanvas(_ palette: ThemePalette) -> some View {
        if palette.id == .liquidGlass {
            self.background(LivingMeshBackground())
        } else {
            self.themedCanvas(palette)
        }
    }
}
