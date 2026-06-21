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
