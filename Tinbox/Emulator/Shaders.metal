//
//  Shaders.metal
//  Tinbox
//
//  Fullscreen quad; the fragment shader samples the 240×160 emulator texture.
//  filter: 0 = none (nearest), 1 = CRT scanlines, 2 = pixel grid, 3 = Scale2x/EPX
//  smoothing (the "HQ2x" menu option — see README: true HQ2x is not implemented).
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 quadScale;     // NDC scale of the quad (1,1 == fill the view)
    float2 textureSize;   // 240, 160
    float2 outputSize;    // on-screen pixels covered by the quad
    int    filter;
    float  opacity;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut tinbox_vertex(uint vid [[vertex_id]],
                               constant Uniforms& u [[buffer(0)]]) {
    // Two triangles covering [-1,1]^2, scaled to the letterboxed quad.
    float2 corners[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2( 1, -1), float2( 1,  1), float2(-1,  1)
    };
    float2 p = corners[vid];
    VertexOut out;
    out.position = float4(p * u.quadScale, 0, 1);
    out.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return out;
}

static inline float4 tex_nearest(texture2d<float> tex, float2 uv) {
    constexpr sampler s(coord::normalized, filter::nearest, address::clamp_to_edge);
    return tex.sample(s, uv);
}

static inline bool same(float4 a, float4 b) {
    return all(abs(a.rgb - b.rgb) < 0.02);
}

/// Scale2x / EPX: pick a neighbour when the two adjacent edge pixels agree and
/// the opposite ones do not. Evaluated per output pixel on a 2× virtual grid.
static float4 scale2x(texture2d<float> tex, float2 uv, float2 texSize) {
    float2 texel = 1.0 / texSize;
    float2 pos = uv * texSize;
    float2 base = floor(pos);
    float2 frac = pos - base;
    float2 c = (base + 0.5) * texel;

    float4 P = tex_nearest(tex, c);
    float4 A = tex_nearest(tex, c + float2(0, -texel.y));
    float4 B = tex_nearest(tex, c + float2(texel.x, 0));
    float4 C = tex_nearest(tex, c + float2(-texel.x, 0));
    float4 D = tex_nearest(tex, c + float2(0, texel.y));

    bool left = frac.x < 0.5;
    bool top = frac.y < 0.5;
    float4 out = P;
    if (top && left)   { if (same(C, A) && !same(C, D) && !same(A, B)) out = A; }
    if (top && !left)  { if (same(A, B) && !same(A, C) && !same(B, D)) out = B; }
    if (!top && left)  { if (same(D, C) && !same(D, B) && !same(C, A)) out = C; }
    if (!top && !left) { if (same(B, D) && !same(B, A) && !same(D, C)) out = D; }
    return out;
}

fragment float4 tinbox_fragment(VertexOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant Uniforms& u [[buffer(0)]]) {
    float4 color;
    if (u.filter == 3) {
        color = scale2x(tex, in.uv, u.textureSize);
    } else {
        color = tex_nearest(tex, in.uv);
    }

    if (u.filter == 1) {
        // CRT: darken every other emulated scanline, with a soft phosphor feel.
        float line = in.uv.y * u.textureSize.y;
        float scan = 0.5 + 0.5 * cos(line * 2.0 * M_PI_F);
        float darken = mix(0.68, 1.0, scan);
        // Subtle horizontal bleed.
        float2 texel = 1.0 / u.textureSize;
        float4 l = tex_nearest(tex, in.uv - float2(texel.x * 0.5, 0));
        float4 r = tex_nearest(tex, in.uv + float2(texel.x * 0.5, 0));
        color.rgb = (color.rgb * 0.6 + (l.rgb + r.rgb) * 0.2) * darken;
        color.rgb *= 1.08;
    } else if (u.filter == 2) {
        // Grid: thin dark lines between emulated pixels, visible only when the
        // on-screen scale is ≥ 2px per texel.
        float2 scale = u.outputSize / u.textureSize;
        float2 f = fract(in.uv * u.textureSize);
        float2 px = f * scale;
        float lineW = 1.0;
        float g = 1.0;
        if (scale.x >= 2.0 && px.x < lineW) g *= 0.72;
        if (scale.y >= 2.0 && px.y < lineW) g *= 0.72;
        color.rgb *= g;
    }

    return float4(color.rgb, u.opacity);
}
