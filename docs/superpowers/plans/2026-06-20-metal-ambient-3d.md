# Metal Ambient 3D (Particles + Orbs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two GPU-driven Metal background layers to the Avenor Mac app — a reactive particle field behind the capture bar, and ambient floating orbs behind the Overview title block — as pure atmospheric additions with zero logic, data-model, or service-layer changes.

**Architecture:** Two self-contained Metal rendering stacks, each = one `.metal` shader file + one `MTKView` subclass + one renderer (Metal state manager) + one `NSViewRepresentable` SwiftUI wrapper. Both views are transparent (`isOpaque = false`, clear background) and sit *behind* existing SwiftUI content. Particles use a compute shader + additive point-sprite render with triple-buffered position buffers; orbs use a fullscreen-quad gaussian fragment shader with Lissajous drift computed CPU-side and passed as uniforms.

**Tech Stack:** SwiftUI, Metal (MTKView / MTLDevice / MTLCommandQueue / MTLLibrary / MTLComputePipelineState / MTLRenderPipelineState), MetalKit. macOS 13+. Zero third-party dependencies.

## Design Read

Reading this as: atmospheric 3D that makes the app feel alive — particles and orbs as ambient presence, not visual noise. Metal-native, 60fps locked, mint-accented.

## Global Constraints

- Zero third-party dependencies — Metal + SwiftUI + MetalKit only. **No SceneKit, RealityKit, SpriteKit, SPM, or CocoaPods.**
- All shader colors are exactly two `float4` values, no others:
  - mint = `float4(0.431, 0.906, 0.659, 1.0)` (verified against `Mac_Accent.mint` = `Color(red: 110/255, green: 231/255, blue: 168/255)` in `PlannerMac/Mac_ContentView.swift:13`)
  - violet = `float4(0.486, 0.227, 0.929, 1.0)`
- Particle count: 1000 default, **never exceed 1200**.
- GPU memory: particle buffer ≤ 256 KB; orb uniforms ≤ 4 KB.
- Triple buffering for particle position buffers — no CPU↔GPU sync stalls.
- Both Metal views: `isOpaque = false`, `layer.isOpaque = false`, `clearColor = MTLClearColorMake(0,0,0,0)` — transparent overlays.
- Additive blending for particles (`.one` / `.one`); standard premultiplied alpha blending for orbs.
- `accessibilityReduceMotion`: read `@Environment(\.accessibilityReduceMotion)` in Swift, pass a `bool` uniform to every shader, and provide a static fallback at every animation site — no exceptions.
- Frame budget: particles alone ≤ 8 ms; particles + orbs combined ≤ 12 ms on Apple Silicon.
- Build: zero errors, zero warnings — including Metal shader compiler warnings.
- Do **not** touch: any iOS file, any service / mutator / data-model file, `DesignTokens.swift`, `ThemePalette.swift`, or any `PlannerMac/` file other than `Mac_CaptureBar.swift` and `Mac_OverviewPane.swift`.
- New files belong to the **PlannerMac** target only (not Planner / iOS, not the widget). `.metal` files must be in PlannerMac's *Compile Sources* build phase so they compile into the target's `default.metallib`.

---

## Codebase Integration Notes (read before Task 1)

These are the three places the spec's assumptions diverge from the actual code. Honor the real structure.

**1. The capture bar is NOT a ZStack.** `Mac_CaptureBar.body` (`PlannerMac/Mac_CaptureBar.swift:36-72`) is an `HStack` followed by a chain of `.background(...)` / `.overlay(...)` modifiers, ending in `.clipShape(shape)`. The integration is therefore an **additional `.background(...)` layer inserted immediately after the `.ultraThinMaterial` background (line 69) and before `.overlay(specular(...))` (line 70)** — this places particles *behind* the translucent material (so they glow through it faintly) and inside the `.clipShape(shape)` (so they are clipped to the bar's rounded rect). This is "adding a background layer," not restructuring.

**2. Focus state is `@FocusState private var focused: Bool`** (line 30), not a binding named `isFocused`. Wire `triggerFocus()` / `triggerIdle()` via `.onChange(of: focused)`. The capture submit already routes through `commit()` via `.onSubmit(commit)` (line 50) — call `triggerCapture()` from inside `commit()` on the success path (right where the existing mint `flash` is set, line 209), so a burst fires only on an *accepted* capture, matching the existing flash semantics.

**3. The Overview pane uses an opaque `.themedCanvas(p)`** (`PlannerMac/Mac_OverviewPane.swift:126`), which paints the full canvas color behind the content. Orbs placed behind that modifier would be fully occluded. The pane's palette exposes `canvasView` (`Planner/DesignSystem/ThemePalette.swift:262`) — a standalone full-bleed canvas layer "for composing the background as an explicit sibling at the base of a `ZStack`." Integration: wrap the existing `ScrollView` in a `ZStack` whose layers, bottom→top, are: `p.canvasView` (opaque base) → orb representable (constrained to top 200 pt) → the `ScrollView` *with its `.themedCanvas(p)` removed*. This is the sanctioned pattern for this exact situation; it adds a background ZStack layer and swaps one opaque modifier for the equivalent explicit base layer. Net visual backdrop is identical; orbs now render in the gap between canvas and content.

**4. Adding files to the project — automatic.** The `PlannerMac` and `PlannerMacTests` groups are **`PBXFileSystemSynchronizedRootGroup`s** (verified in `Planner.xcodeproj/project.pbxproj`). Any file created under `PlannerMac/` (including a new `PlannerMac/Metal/` subfolder) is automatically compiled into the PlannerMac target; any file under `PlannerMacTests/` auto-joins the test target. **No `project.pbxproj` editing and no manual Target Membership step is required** — just create the file at the right path. `.metal` files placed under `PlannerMac/` compile into the target's `default.metallib`, which `device.makeDefaultLibrary()` loads at runtime. (Do not edit `project.pbxproj`; doing so by hand on a synchronized project can corrupt it.)

---

## File Structure

New files (all PlannerMac target):

| File | Responsibility |
|------|----------------|
| `PlannerMac/Metal/AvenorParticles.metal` | Particle compute shader (`updateParticles`) + point-sprite vertex/fragment (`particleVertex`/`particleFragment`); shared `Particle` and `Uniforms` layout |
| `PlannerMac/Metal/ParticleRenderer.swift` | Metal state owner: device, queue, compute + render pipelines, 3× particle buffers, uniform buffer; seeds particles; encodes a frame |
| `PlannerMac/Metal/MetalParticleView.swift` | `MTKView` subclass: triple-buffer semaphore, 60 fps, `triggerFocus/Capture/Idle`, size→center recompute |
| `PlannerMac/Metal/MetalParticleViewRepresentable.swift` | `NSViewRepresentable` bridging `MetalParticleView` into SwiftUI; passes `reduceMotion` |
| `PlannerMac/Metal/AvenorOrbs.metal` | Orb fragment shader (`orbFragment`) + passthrough fullscreen-quad vertex (`orbVertex`); `OrbUniforms` layout |
| `PlannerMac/Metal/OrbRenderer.swift` | Metal state owner: device, queue, render pipeline, orb uniform buffer; Lissajous CPU update; encodes a frame |
| `PlannerMac/Metal/MetalOrbView.swift` | `MTKView` subclass: 30 fps, 3 seeded orbs, `fadeIn(duration:)` global-opacity ramp |
| `PlannerMac/Metal/MetalOrbViewRepresentable.swift` | `NSViewRepresentable` bridging `MetalOrbView`; passes `reduceMotion`, triggers `fadeIn` |
| `PlannerMacTests/MetalAmbientTests.swift` | Pure-Swift unit tests: buffer-byte budget, uniform memory-layout/stride, Lissajous position math |

Modified files:

| File | Change |
|------|--------|
| `PlannerMac/Mac_CaptureBar.swift` | One `@State` particle view; one `.background(...)` layer after `.ultraThinMaterial`; `.onChange(of: focused)`; `triggerCapture()` in `commit()` success path |
| `PlannerMac/Mac_OverviewPane.swift` | Wrap `ScrollView` in `ZStack`, base `p.canvasView`, orb layer constrained to top 200 pt, `fadeIn` on appear; remove `.themedCanvas(p)` from the ScrollView (replaced by base layer) |

A shared header (`Particle`, `ParticleUniforms`, `OrbUniforms`) is duplicated between the `.metal` files and the Swift renderers by hand (Metal has no bridging header here); the unit tests in Task 1 lock the Swift-side struct sizes so the two never silently drift.

---

## A note on testing GPU code

Shader output and on-GPU motion cannot be meaningfully asserted in XCTest — those behaviors are validated by the **manual GPU-capture gates** at the end of each Element. What *is* unit-testable is the pure-Swift contract around the GPU: byte budgets (constraint compliance), uniform memory layout/stride (so Swift and `.metal` structs agree), and the Lissajous position function (extracted as a free function). Task 1 writes those real tests first (TDD); rendering tasks that follow are gated by build-clean + the visual/GPU acceptance checks, which are spelled out as explicit verification steps rather than fabricated assertions.

---

## Task 1: Layout contracts & math (pure Swift, TDD)

Establishes the byte budgets, the uniform memory layout shared with the shaders, and the Lissajous drift function — all independently testable before any Metal object exists. Produces the type definitions later tasks import.

**Files:**
- Create: `PlannerMac/Metal/ParticleRenderer.swift` (types only in this task)
- Create: `PlannerMac/Metal/OrbRenderer.swift` (types + free function only in this task)
- Test: `PlannerMacTests/MetalAmbientTests.swift`

**Interfaces:**
- Produces (consumed by Tasks 2–8):
  - `struct Particle { var position: SIMD2<Float>; var velocity: SIMD2<Float>; var life: Float; var size: Float; var opacity: Float }`
  - `struct ParticleUniforms { var mode: Int32; var captureBarCenter: SIMD2<Float>; var deltaTime: Float; var reduceMotion: Bool }`
  - `enum ParticleConstants { static let count = 1000; static let maxCount = 1200 }`
  - `struct OrbUniforms { var center: SIMD2<Float>; var radius: Float; var color: SIMD4<Float>; var opacity: Float; var time: Float; var globalOpacity: Float }`
  - `func lissajousCenter(base: SIMD2<Float>, amplitude: SIMD2<Float>, freq: SIMD2<Float>, phase: SIMD2<Float>, time: Float) -> SIMD2<Float>`

- [ ] **Step 1: Write the failing tests**

Create `PlannerMacTests/MetalAmbientTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests, verify they fail to compile**

Run: `xcodebuild test -scheme PlannerMac -destination 'platform=macOS' -only-testing:PlannerMacTests/MetalAmbientTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'Particle' / 'ParticleConstants' / 'OrbUniforms' / 'lissajousCenter' in scope`.

- [ ] **Step 3: Define the types and function**

In `PlannerMac/Metal/ParticleRenderer.swift` (top of file, class body added in Task 3):

```swift
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
```

In `PlannerMac/Metal/OrbRenderer.swift` (top of file, class body added in Task 6):

```swift
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
```

Create both files under `PlannerMac/Metal/` and the test under `PlannerMacTests/`; they auto-join their targets via the synchronized groups (Integration Note 4) — no Target Membership step.

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme PlannerMac -destination 'platform=macOS' -only-testing:PlannerMacTests/MetalAmbientTests 2>&1 | tail -20`
Expected: PASS — 5 tests. If `test_orbUniforms_withinByteBudget` or `test_particleBuffer_withinByteBudget` fails, the budgets are blown — do not "fix" the test; the struct is wrong.

- [ ] **Step 5: Commit**

```bash
git add PlannerMac/Metal/ParticleRenderer.swift PlannerMac/Metal/OrbRenderer.swift PlannerMacTests/MetalAmbientTests.swift
git commit -m "feat(mac): Metal ambient layout contracts + Lissajous math (tested)"
```

---

# ELEMENT 1 — Particle System (Capture Bar)

Complete Element 1 and confirm its gate before starting Element 2.

## Task 2: Particle shaders (`AvenorParticles.metal`)

The compute + render shader stages. No Swift side yet — this task is gated by "the file compiles into the metallib with zero warnings," verified by a target build in Task 3 (shaders aren't independently runnable). Written here as a complete unit so Task 3 can wire pipelines to named functions.

**Files:**
- Create: `PlannerMac/Metal/AvenorParticles.metal`

**Interfaces:**
- Produces (consumed by Task 3 pipeline creation):
  - compute kernel `updateParticles`
  - vertex function `particleVertex`, fragment function `particleFragment`
  - `Particle` / `Uniforms` struct layout matching the Swift mirror from Task 1

- [ ] **Step 1: Write the shader file**

```metal
#include <metal_stdlib>
using namespace metal;

constant float4 kMint = float4(0.431, 0.906, 0.659, 1.0);

struct Particle {
    float2 position;
    float2 velocity;
    float  life;
    float  size;
    float  opacity;
};

struct Uniforms {
    int    mode;            // 0 idle, 1 focus, 2 capture
    float2 captureBarCenter;
    float  deltaTime;
    bool   reduceMotion;
};

// Cheap hash → pseudo-random in [0,1), stable per index/seed.
static float hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

kernel void updateParticles(device Particle      *particles [[buffer(0)]],
                            constant Uniforms    &u         [[buffer(1)]],
                            constant float2      &bounds    [[buffer(2)]],
                            uint                  id        [[thread_position_in_grid]])
{
    Particle p = particles[id];

    if (u.reduceMotion) {
        // Static fallback — no velocity integration at all.
        particles[id] = p;
        return;
    }

    float fid = float(id);

    if (u.mode == 1) {
        // Focus: gravity well toward the bar center, capped force.
        float2 toCenter = u.captureBarCenter - p.position;
        float dist = max(length(toCenter), 50.0);
        float2 dir = normalize(toCenter);
        float2 force = dir * 0.3 * (1.0 / dist);
        float mag = min(length(force), 0.8);
        p.velocity += normalize(force + float2(1e-6)) * mag;
    } else if (u.mode == 2) {
        // Capture: one-shot radial impulse outward, magnitude 2..5 by index.
        float2 dir = normalize(p.position - u.captureBarCenter + float2(1e-6));
        float impulse = 2.0 + 3.0 * hash11(fid);
        p.velocity += dir * impulse;
    } else {
        // Idle: Brownian perturbation + slow upward drift.
        float jitterX = (hash11(fid + u.deltaTime * 60.0) - 0.5) * 0.06;
        float jitterY = (hash11(fid * 1.7 + u.deltaTime * 60.0) - 0.5) * 0.06;
        p.velocity += float2(jitterX, jitterY);
        p.velocity.y -= 0.0003;
    }

    // Integrate + damp (damping decays the capture impulse over ~1.2s).
    p.position += p.velocity;
    p.velocity *= 0.98;

    // Wrap on all edges (bounds = drawable size in pixels).
    if (p.position.x < 0)         p.position.x += bounds.x;
    if (p.position.x > bounds.x)  p.position.x -= bounds.x;
    if (p.position.y < 0)         p.position.y += bounds.y;
    if (p.position.y > bounds.y)  p.position.y -= bounds.y;

    particles[id] = p;
}

struct VSOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float  opacity;
};

vertex VSOut particleVertex(const device Particle *particles [[buffer(0)]],
                            constant float2        &bounds    [[buffer(1)]],
                            constant Uniforms      &u         [[buffer(2)]],
                            uint                    vid        [[vertex_id]])
{
    Particle p = particles[vid];
    VSOut out;
    // Pixel space → clip space [-1,1], y up.
    float2 ndc = (p.position / bounds) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = clamp(p.size, 2.0, 4.0);
    // Focus brightens; capture inherits the brightened opacity then damps.
    float base = clamp(p.opacity, 0.15, 0.25);
    float peak = (u.mode == 0) ? base : mix(base, 0.5, 0.6);
    out.opacity = peak;
    return out;
}

fragment float4 particleFragment(VSOut in [[stage_in]],
                                 float2 pointCoord [[point_coord]])
{
    // Soft round sprite: radial falloff from center of the point.
    float d = length(pointCoord - float2(0.5));
    float a = smoothstep(0.5, 0.0, d) * in.opacity;
    // Additive blend in the pipeline; premultiply by alpha here.
    return float4(kMint.rgb * a, a);
}
```

- [ ] **Step 2: Add to target & build**

Create `AvenorParticles.metal` under `PlannerMac/Metal/` — it auto-compiles into the target via the synchronized group (Integration Note 4).
Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "metal|warning|error" | head -30`
Expected: no `metal:` errors, no warnings. (The shader is unused for now; that is not a warning.)

- [ ] **Step 3: Commit**

```bash
git add PlannerMac/Metal/AvenorParticles.metal
git commit -m "feat(mac): particle compute + point-sprite shaders"
```

---

## Task 3: Particle renderer (`ParticleRenderer.swift`)

Owns all Metal objects for particles and encodes one frame (compute → render). Builds on the type definitions added to this same file in Task 1.

**Files:**
- Modify: `PlannerMac/Metal/ParticleRenderer.swift` (append the class below the Task-1 types)

**Interfaces:**
- Consumes: `Particle`, `ParticleUniforms`, `ParticleConstants` (Task 1); `updateParticles`, `particleVertex`, `particleFragment` (Task 2)
- Produces (consumed by Task 4):
  - `final class ParticleRenderer`
  - `init?(device: MTLDevice)`
  - `func resize(to size: CGSize)` — recompute pixel bounds + default bar center
  - `func draw(in view: MTKView, mode: Int, captureBarCenter: SIMD2<Float>, reduceMotion: Bool, semaphore: DispatchSemaphore)`

- [ ] **Step 1: Append the renderer class**

```swift
import MetalKit

final class ParticleRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState

    // Triple-buffered particle storage.
    private static let bufferCount = 3
    private var particleBuffers: [MTLBuffer] = []
    private var bufferIndex = 0

    private var bounds = SIMD2<Float>(600, 60)
    private var defaultCenter = SIMD2<Float>(300, 30)
    private var lastFrameTime = CACurrentMediaTime()

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let compute = library.makeFunction(name: "updateParticles"),
              let vfn = library.makeFunction(name: "particleVertex"),
              let ffn = library.makeFunction(name: "particleFragment")
        else { return nil }
        self.queue = queue

        do {
            computePipeline = try device.makeComputePipelineState(function: compute)
        } catch { return nil }

        let rp = MTLRenderPipelineDescriptor()
        rp.vertexFunction = vfn
        rp.fragmentFunction = ffn
        let att = rp.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one      // additive
        att.destinationRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .one
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: rp)
        } catch { return nil }

        seedBuffers()
    }

    private func seedBuffers() {
        let n = ParticleConstants.count
        var seed = [Particle]()
        seed.reserveCapacity(n)
        for _ in 0..<n {
            let r1 = Float.random(in: 0...1), r2 = Float.random(in: 0...1)
            seed.append(Particle(
                position: SIMD2<Float>(r1 * bounds.x, r2 * bounds.y),
                velocity: .zero,
                life: 1,
                size: Float.random(in: 2...4),
                opacity: Float.random(in: 0.15...0.25)))
        }
        let len = MemoryLayout<Particle>.stride * n
        particleBuffers = (0..<Self.bufferCount).compactMap {
            _ in device.makeBuffer(bytes: seed, length: len, options: .storageModeShared)
        }
    }

    func resize(to size: CGSize) {
        bounds = SIMD2<Float>(max(Float(size.width), 1), max(Float(size.height), 1))
        defaultCenter = bounds * 0.5
    }

    func draw(in view: MTKView, mode: Int, captureBarCenter: SIMD2<Float>,
              reduceMotion: Bool, semaphore: DispatchSemaphore) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer() else { semaphore.signal(); return }

        let now = CACurrentMediaTime()
        let dt = Float(now - lastFrameTime)
        lastFrameTime = now

        let center = (captureBarCenter == .zero) ? defaultCenter : captureBarCenter
        var u = ParticleUniforms(mode: Int32(mode), captureBarCenter: center,
                                 deltaTime: dt, reduceMotion: reduceMotion)
        var bnds = bounds

        bufferIndex = (bufferIndex + 1) % Self.bufferCount
        let buf = particleBuffers[bufferIndex]

        // Compute pass.
        if let ce = cmd.makeComputeCommandEncoder() {
            ce.setComputePipelineState(computePipeline)
            ce.setBuffer(buf, offset: 0, index: 0)
            ce.setBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
            ce.setBytes(&bnds, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            let w = computePipeline.maxTotalThreadsPerThreadgroup
            ce.dispatchThreads(MTLSize(width: ParticleConstants.count, height: 1, depth: 1),
                               threadsPerThreadgroup: MTLSize(width: min(w, 256), height: 1, depth: 1))
            ce.endEncoding()
        }

        // Render pass.
        if let re = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            re.setRenderPipelineState(renderPipeline)
            re.setVertexBuffer(buf, offset: 0, index: 0)
            re.setVertexBytes(&bnds, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            re.setVertexBytes(&u, length: MemoryLayout<ParticleUniforms>.stride, index: 2)
            re.drawPrimitives(type: .point, vertexStart: 0, vertexCount: ParticleConstants.count)
            re.endEncoding()
        }

        cmd.addCompletedHandler { _ in semaphore.signal() }
        cmd.present(drawable)
        cmd.commit()
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "error|warning" | head -20`
Expected: no errors, no warnings.

- [ ] **Step 3: Commit**

```bash
git add PlannerMac/Metal/ParticleRenderer.swift
git commit -m "feat(mac): triple-buffered particle renderer"
```

---

## Task 4: Particle MTKView (`MetalParticleView.swift`)

The `MTKView` subclass driving the render loop at 60 fps with a triple-buffer semaphore, and exposing the focus/capture/idle triggers.

**Files:**
- Create: `PlannerMac/Metal/MetalParticleView.swift`

**Interfaces:**
- Consumes: `ParticleRenderer` (Task 3)
- Produces (consumed by Task 5):
  - `final class MetalParticleView: MTKView, MTKViewDelegate`
  - `func triggerFocus()`, `func triggerCapture()`, `func triggerIdle()`
  - `var reduceMotion: Bool`

- [ ] **Step 1: Write the view**

```swift
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
        isOpaque = false
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
        semaphore.wait()
        // mode 0 passes .zero so the renderer uses its computed default center;
        // focus/capture pass the live bar center (current bounds midpoint).
        let activeCenter: SIMD2<Float> = (mode == 0)
            ? .zero
            : SIMD2<Float>(Float(bounds.midX), Float(bounds.midY))
        renderer?.draw(in: view, mode: mode, captureBarCenter: activeCenter,
                       reduceMotion: reduceMotion, semaphore: semaphore)
        if captureResetPending {     // capture is a one-frame impulse → back to focus
            captureResetPending = false
            mode = 1
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "error|warning" | head -20`
Expected: no errors, no warnings.

- [ ] **Step 3: Commit**

```bash
git add PlannerMac/Metal/MetalParticleView.swift
git commit -m "feat(mac): MetalParticleView render loop + triggers"
```

---

## Task 5: Particle SwiftUI wrapper + capture-bar integration

Bridges the view into SwiftUI and wires it into `Mac_CaptureBar` as a background layer with focus/capture/idle triggers. This is the Element 1 deliverable a reviewer judges visually.

**Files:**
- Create: `PlannerMac/Metal/MetalParticleViewRepresentable.swift`
- Modify: `PlannerMac/Mac_CaptureBar.swift`

**Interfaces:**
- Consumes: `MetalParticleView` (Task 4)
- Produces: `struct MetalParticleViewRepresentable: NSViewRepresentable`

- [ ] **Step 1: Write the representable**

`PlannerMac/Metal/MetalParticleViewRepresentable.swift`:

```swift
import SwiftUI
import MetalKit

struct MetalParticleViewRepresentable: NSViewRepresentable {
    let view: MetalParticleView
    var reduceMotion: Bool

    func makeNSView(context: Context) -> MetalParticleView {
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ nsView: MetalParticleView, context: Context) {
        nsView.reduceMotion = reduceMotion
    }
}
```

- [ ] **Step 2: Hold the view and add the background layer**

In `Mac_CaptureBar.swift`, add a stored view alongside the other `@State` (near line 30):

```swift
    @State private var particleView = MetalParticleView()
```

Insert the particle layer **after** the `.ultraThinMaterial` background (current line 69) and **before** `.overlay(specular(shape))` (current line 70). Replace:

```swift
        .background(shape.fill(.ultraThinMaterial))
        .overlay(specular(shape))
```

with:

```swift
        .background(shape.fill(.ultraThinMaterial))
        .background(
            MetalParticleViewRepresentable(view: particleView, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .clipShape(shape)
        )
        .overlay(specular(shape))
```

- [ ] **Step 3: Wire focus and capture triggers**

Add an `.onChange(of: focused)` next to the existing `.onAppear { focused = true }` (current line 77):

```swift
        .onChange(of: focused) { _, isFocused in
            isFocused ? particleView.triggerFocus() : particleView.triggerIdle()
        }
```

In `commit()`, fire the burst on the **success path only** — at the existing flash site (current lines 208–212), change:

```swift
        // Mint capture flash, then fade back to idle.
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            flash = false
        }
```

to:

```swift
        // Mint capture flash + particle burst, then fade back to idle.
        flash = true
        particleView.triggerCapture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            flash = false
        }
```

(The bar auto-focuses on appear, so a successful capture leaves `focused == true`; `triggerCapture()` returns the particles to mode 1/focus after the one-frame impulse, which matches.)

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "error|warning" | head -20`
Expected: no errors, no warnings.

- [ ] **Step 5: Manual visual gate (Element 1)**

Launch the app (Xcode ▶ on PlannerMac). Verify:
- [ ] Particles faintly visible behind the capture bar at rest (slow Brownian drift upward).
- [ ] Clicking the bar (focus) → particles drift toward bar center.
- [ ] Pressing Enter on a valid capture → particles burst outward, settle over ~1.2 s.
- [ ] System Settings → Accessibility → Display → **Reduce Motion ON** → particles static, no drift.

- [ ] **Step 6: GPU capture gate (Element 1)**

In Xcode: Debug → Capture GPU Frame while the bar is focused. Verify:
- [ ] Frame time ≤ 8 ms on Apple Silicon.
- [ ] Three distinct particle buffers cycle across frames (no buffer reused within a 3-frame window) — confirms triple buffering, no CPU↔GPU stall.

- [ ] **Step 7: Commit**

```bash
git add PlannerMac/Metal/MetalParticleViewRepresentable.swift PlannerMac/Mac_CaptureBar.swift
git commit -m "feat(mac): wire particle field into capture bar"
```

**Element 1 Gate output:** `✅ Element 1 complete — additive mint point sprites, gravity-well focus, one-frame radial burst with 0.98 damping; frame time [X]ms; triple buffering confirmed.`

---

# ELEMENT 2 — Floating Orbs (Overview Pane)

Begin only after the Element 1 gate is confirmed.

## Task 6: Orb shaders + renderer (`AvenorOrbs.metal`, `OrbRenderer.swift`)

Gaussian-blob fragment shader over a fullscreen quad, one draw call per orb, plus the renderer that updates Lissajous centers (via the Task-1 function) and encodes the frame. Bundled because the shader function names and the renderer that binds them are a single reviewable unit.

**Files:**
- Create: `PlannerMac/Metal/AvenorOrbs.metal`
- Modify: `PlannerMac/Metal/OrbRenderer.swift` (append class below Task-1 types)

**Interfaces:**
- Consumes: `OrbUniforms`, `lissajousCenter` (Task 1)
- Produces (consumed by Task 7):
  - vertex `orbVertex`, fragment `orbFragment`
  - `struct OrbConfig { var base, amplitude, freq, phase: SIMD2<Float>; var radius, opacity: Float; var color: SIMD4<Float> }`
  - `final class OrbRenderer` with `init?(device:, orbs: [OrbConfig])`, `func resize(to:)`, `func draw(in:elapsedTime:globalOpacity:reduceMotion:)`, and static `mint` / `violet` colors

- [ ] **Step 1: Write the shader file**

`PlannerMac/Metal/AvenorOrbs.metal`:

```metal
#include <metal_stdlib>
using namespace metal;

struct OrbUniforms {
    float2 center;
    float  radius;
    float4 color;
    float  opacity;
    float  time;
    float  globalOpacity;
};

struct OrbVSOut {
    float4 position [[position]];
    float2 pixel;            // fragment position in pixel space
};

// Fullscreen quad from vertex_id (two triangles, 6 verts). drawableSize in pixels.
vertex OrbVSOut orbVertex(constant float2 &drawableSize [[buffer(0)]],
                          uint vid [[vertex_id]]) {
    float2 corners[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1,  1), float2(1, -1), float2(1,  1)
    };
    float2 c = corners[vid];
    OrbVSOut out;
    out.position = float4(c, 0, 1);
    // clip → pixel space (y down to match center coords)
    float2 uv = (c * 0.5 + 0.5);
    out.pixel = float2(uv.x * drawableSize.x, (1.0 - uv.y) * drawableSize.y);
    return out;
}

fragment float4 orbFragment(OrbVSOut in [[stage_in]],
                            constant OrbUniforms &u [[buffer(0)]]) {
    float d = distance(in.pixel, u.center);
    float a = exp(-(d * d) / (u.radius * u.radius)) * u.opacity * u.globalOpacity;
    // Premultiplied alpha (standard blend in the pipeline).
    return float4(u.color.rgb * a, a);
}
```

- [ ] **Step 2: Append the renderer to `OrbRenderer.swift`**

Append below the Task-1 types:

```swift
import MetalKit

struct OrbConfig {
    var base: SIMD2<Float>
    var amplitude: SIMD2<Float>
    var freq: SIMD2<Float>
    var phase: SIMD2<Float>
    var radius: Float
    var opacity: Float
    var color: SIMD4<Float>
}

final class OrbRenderer {
    static let mint   = SIMD4<Float>(0.431, 0.906, 0.659, 1.0)
    static let violet = SIMD4<Float>(0.486, 0.227, 0.929, 1.0)

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var configs: [OrbConfig]
    private var size = SIMD2<Float>(600, 200)

    init?(device: MTLDevice, orbs: [OrbConfig]) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "orbVertex"),
              let ffn = library.makeFunction(name: "orbFragment")
        else { return nil }
        self.queue = queue
        self.configs = orbs

        let rp = MTLRenderPipelineDescriptor()
        rp.vertexFunction = vfn
        rp.fragmentFunction = ffn
        let att = rp.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one              // premultiplied
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do { pipeline = try device.makeRenderPipelineState(descriptor: rp) }
        catch { return nil }
    }

    func resize(to s: CGSize) {
        size = SIMD2<Float>(max(Float(s.width), 1), max(Float(s.height), 1))
    }

    func draw(in view: MTKView, elapsedTime: Float, globalOpacity: Float, reduceMotion: Bool) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        var ds = size
        enc.setVertexBytes(&ds, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)

        for c in configs {
            let center = reduceMotion
                ? c.base
                : lissajousCenter(base: c.base, amplitude: c.amplitude,
                                  freq: c.freq, phase: c.phase, time: elapsedTime)
            var u = OrbUniforms(center: center, radius: c.radius, color: c.color,
                                opacity: c.opacity, time: elapsedTime,
                                globalOpacity: globalOpacity)
            enc.setFragmentBytes(&u, length: MemoryLayout<OrbUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
```

- [ ] **Step 3: Add `AvenorOrbs.metal` to target & build**

Create `AvenorOrbs.metal` under `PlannerMac/Metal/` — auto-compiles via the synchronized group (Integration Note 4).
Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "metal|error|warning" | head -20`
Expected: no errors, no warnings.

- [ ] **Step 4: Commit**

```bash
git add PlannerMac/Metal/AvenorOrbs.metal PlannerMac/Metal/OrbRenderer.swift
git commit -m "feat(mac): orb gaussian shader + Lissajous renderer"
```

---

## Task 7: Orb MTKView (`MetalOrbView.swift`)

30 fps `MTKView` subclass seeding the three orbs and owning the fade-in ramp.

**Files:**
- Create: `PlannerMac/Metal/MetalOrbView.swift`

**Interfaces:**
- Consumes: `OrbRenderer`, `OrbConfig` (Task 6)
- Produces (consumed by Task 8):
  - `final class MetalOrbView: MTKView, MTKViewDelegate`
  - `func fadeIn(duration: Double)`, `var reduceMotion: Bool`

- [ ] **Step 1: Write the view**

```swift
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
        isOpaque = false
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
```

(Note: `resolve` multiplies the 0..1 base by the orb view's pixel size; since `OrbConfig.base` is re-resolved on every `drawableSizeWillChange`, the orbs stay anchored to the title band across window resizes. Lissajous amplitudes/radii stay in absolute pixels by design.)

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "error|warning" | head -20`
Expected: no errors, no warnings.

- [ ] **Step 3: Commit**

```bash
git add PlannerMac/Metal/MetalOrbView.swift
git commit -m "feat(mac): MetalOrbView with 3 seeded orbs + fade-in"
```

---

## Task 8: Orb SwiftUI wrapper + Overview integration

Bridges orbs into SwiftUI and composes them into the Overview pane *above* the canvas fill and *below* the content (Integration Note 3). Element 2 deliverable.

**Files:**
- Create: `PlannerMac/Metal/MetalOrbViewRepresentable.swift`
- Modify: `PlannerMac/Mac_OverviewPane.swift`

**Interfaces:**
- Consumes: `MetalOrbView` (Task 7)
- Produces: `struct MetalOrbViewRepresentable: NSViewRepresentable`

- [ ] **Step 1: Write the representable**

`PlannerMac/Metal/MetalOrbViewRepresentable.swift`:

```swift
import SwiftUI
import MetalKit

struct MetalOrbViewRepresentable: NSViewRepresentable {
    let view: MetalOrbView
    var reduceMotion: Bool

    func makeNSView(context: Context) -> MetalOrbView {
        view.reduceMotion = reduceMotion
        return view
    }

    func updateNSView(_ nsView: MetalOrbView, context: Context) {
        nsView.reduceMotion = reduceMotion
    }
}
```

- [ ] **Step 2: Add state + reduceMotion env to the pane**

In `Mac_OverviewPane`, add alongside the other `@Environment`/`@State` (near lines 18–30):

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var orbView = MetalOrbView()
```

- [ ] **Step 3: Compose orbs into the background**

In `body`, the current structure (lines 86–131) is `ScrollView { … }.themedCanvas(p).task{…}.onChange{…}`. Replace the `.themedCanvas(p)` modifier with an explicit ZStack base + orb layer. Change:

```swift
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // … unchanged content …
            }
            // … unchanged padding …
        }
        .themedCanvas(p)
        .task { await refreshEvents() }
        .onChange(of: nav.selection) { _, pane in
            if pane == .overview { Task { await refreshEvents() } }
        }
```

to:

```swift
        ZStack(alignment: .top) {
            p.canvasView                                   // opaque base (was .themedCanvas)
            MetalOrbViewRepresentable(view: orbView, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // … unchanged content …
                }
                // … unchanged padding …
            }
        }
        .task { await refreshEvents() }
        .onAppear { orbView.fadeIn(duration: 0.8) }
        .onChange(of: nav.selection) { _, pane in
            if pane == .overview { Task { await refreshEvents() } }
        }
```

(Leave the `VStack`/content body and its paddings byte-for-byte unchanged — only the wrapping and the `.themedCanvas → canvasView` swap change.)

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -iE "error|warning" | head -20`
Expected: no errors, no warnings.

- [ ] **Step 5: Manual visual gate (Element 2)**

Launch the app, land on Overview. Verify:
- [ ] Three soft orbs (2 mint, 1 violet) visible behind the "Today's Overview" title block, barely perceptible.
- [ ] Orbs fade in over ~0.8 s on pane entry.
- [ ] Orbs drift slowly along Lissajous paths — visible change over 5–10 s.
- [ ] Reduce Motion ON → orbs static at base positions, still visible.
- [ ] Canvas backdrop unchanged everywhere else (no banding, no double-darkening).

- [ ] **Step 6: GPU capture gate (combined)**

With both Overview orbs and (navigate so the bar is focused) particles active, Capture GPU Frame. Verify:
- [ ] Combined frame time ≤ 12 ms on Apple Silicon. If over: profile first, then reduce **particle count** before any other change (Stop Condition).

- [ ] **Step 7: Run the unit tests once more + full build**

Run: `xcodebuild test -scheme PlannerMac -destination 'platform=macOS' -only-testing:PlannerMacTests/MetalAmbientTests 2>&1 | tail -10`
Expected: 5 tests PASS.
Run: `xcodebuild -scheme PlannerMac -destination 'platform=macOS' build 2>&1 | grep -icE "error:|warning:"`
Expected: `0`.

- [ ] **Step 8: Commit**

```bash
git add PlannerMac/Metal/MetalOrbViewRepresentable.swift PlannerMac/Mac_OverviewPane.swift
git commit -m "feat(mac): wire floating orbs into Overview pane"
```

**Element 2 Gate output:** `✅ Element 2 complete — Lissajous freqs {0.013/0.019, 0.021/0.011, 0.009/0.017} rad/s, 0.8s fade-in; combined frame time [X]ms.`

---

## Acceptance Criteria (final checklist)

- [ ] Design read output present (top of this plan).
- [ ] Particles faintly visible at rest behind the capture bar.
- [ ] Particles drift toward bar on focus.
- [ ] Particles burst outward on Enter, return to rest over ~1.2 s.
- [ ] Triple buffering confirmed in GPU Frame Capture — no pipeline stalls.
- [ ] Element 1 frame time ≤ 8 ms on Apple Silicon.
- [ ] Three orbs visible behind "Today's Overview" title block.
- [ ] Orbs fade in over 0.8 s on pane entry.
- [ ] Orbs follow Lissajous paths — visible slow movement.
- [ ] Combined frame time ≤ 12 ms on Apple Silicon.
- [ ] Reduce Motion ON: both elements static.
- [ ] Zero iOS files modified.
- [ ] Zero service / model / data files modified.
- [ ] No existing SwiftUI layout changed beyond adding background ZStack/background layers.
- [ ] Build: zero errors, zero warnings (incl. Metal compiler).
- [ ] `MetalAmbientTests` (5) pass.

## Stop Conditions

Stop and ask before:
- Adding any framework other than Metal + SwiftUI + MetalKit (no SceneKit/RealityKit/SpriteKit).
- Exceeding 1200 particles.
- Applying Metal views to any pane other than the capture bar and Overview.
- Changing any existing SwiftUI layout beyond adding a background layer / wrapping ZStack.
- Touching any iOS file or any service/data file.
- Combined frame time exceeding 12 ms — profile first, reduce particle count before any other optimization.

## Progress

- Design read: ✅ (top of plan)
- Element 1 gate: ⬜ Particles rendering — frame time [X]ms, triple buffering confirmed
- Element 2 gate: ⬜ Orbs rendering — combined frame time [X]ms
- End: one paragraph on what the 3D elements add and what performance decisions were made.
