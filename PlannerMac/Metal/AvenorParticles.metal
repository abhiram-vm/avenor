#include <metal_stdlib>
using namespace metal;

// Pure mint #6EE7A8 — no grey, no white.
constant float4 kMint = float4(0.431, 0.906, 0.659, 1.0);

// CPU mirror: ParticleVertex (Swift). Pixel-space position, point size, opacity.
struct VertexIn {
    float2 position;   // pixels, top-left origin (y down)
    float  size;       // point sprite size in px (2..4)
    float  opacity;    // final per-particle opacity (already includes pulse)
};

struct VSOut {
    float4 position  [[position]];
    float  pointSize [[point_size]];
    float  opacity;
};

// drawableSize passed so we can map pixel space → clip space.
vertex VSOut particleVertex(const device VertexIn *verts [[buffer(0)]],
                            constant float2        &drawableSize [[buffer(1)]],
                            uint                    vid  [[vertex_id]])
{
    VertexIn v = verts[vid];
    VSOut out;
    float2 ndc = (v.position / drawableSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;                       // pixel y-down → clip y-up
    out.position  = float4(ndc, 0.0, 1.0);
    out.pointSize = clamp(v.size, 2.0, 4.0);
    out.opacity   = clamp(v.opacity, 0.0, 1.0);
    return out;
}

fragment float4 particleFragment(VSOut in [[stage_in]],
                                 float2 pc [[point_coord]])
{
    // Gaussian falloff from the sprite center → soft glowing circle.
    float2 d = pc - float2(0.5);
    float  g = exp(-dot(d, d) * 12.0);    // ~0.05 at the edge, 1.0 at center
    float  a = g * in.opacity;
    // Premultiplied mint; additive blend stacks the glow.
    return float4(kMint.rgb * a, a);
}
