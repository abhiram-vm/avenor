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
