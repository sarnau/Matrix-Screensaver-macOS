#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// MARK: Tuning

constant float kFallRate    = 0.4;   // screen heights per second at speed 1, column speed 1
constant float kHeadBoost   = 1.8;   // head brightness (> 1 so bloom picks it up)
constant float kHeadWhite   = 0.7;   // how far the head colour is pushed toward white
constant float kBackground  = 0.03;  // faint residual glyphs between drops
constant float kAtlasCell   = 64.0;  // GlyphAtlas.cellPixels
constant float kExposure    = 1.6;

// MARK: Helpers

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;   // 0…1, origin top-left
};

// PCG hash (Jarzynski & Olano 2020): integer-only, so no precision loss for large inputs.
static uint pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static uint hash2(uint a, uint b) { return pcg(a ^ pcg(b)); }

/// Uniform float in [0, 1).
static float unit(uint h) { return float(h >> 8) * (1.0 / 16777216.0); }

/// One raindrop in column `col`. Returns (brightness, cells behind the head); (0, -1) outside its trail.
static float2 drop(uint col, float row, float rows, float fall, uint salt) {
    float colSpeed = mix(0.6, 1.4, unit(hash2(col, salt)));
    float phase    = unit(hash2(col, salt + 1u));
    float len      = mix(0.3, 0.9, unit(hash2(col, salt + 2u)));   // trail length, screen heights
    float gap      = mix(0.2, 1.2, unit(hash2(col, salt + 3u)));   // dark pause after the trail
    float cycle    = 1.0 + len + gap;                              // distance the head travels per drop
    float headPos  = fract(fall * colSpeed / cycle + phase) * cycle;
    float behind   = floor(headPos * rows) - row;                  // whole cells: the head steps cell by cell
    float trail    = len * rows;
    if (behind < 0.0 || behind >= trail) {
        return float2(0.0, -1.0);
    }
    float b = 1.0 - behind / trail;
    return float2(b * b, behind);
}

// MARK: Shaders

vertex FullscreenOut fullscreenVertex(uint vid [[vertex_id]]) {
    // One oversized triangle covering the viewport: (0,0), (2,0), (0,2) in p-space.
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    FullscreenOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

fragment float4 rainFragment(FullscreenOut in [[stage_in]],
                             constant RainUniforms &u [[buffer(0)]],
                             texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float2 cellF = in.position.xy / u.cellSize;
    float2 cell = floor(cellF);
    float2 local = cellF - cell;
    uint col = uint(cell.x);
    float row = cell.y;
    float fall = u.time * u.speed * kFallRate;

    // Two independent drops per column; the brighter one wins.
    float2 a = drop(col, row, u.grid.y, fall, 0u);
    float2 b = drop(col, row, u.grid.y, fall, 7919u);
    float2 d = a.x >= b.x ? a : b;
    float brightness = d.x;
    float behind = d.y;

    // Glyphs mutate in place at a per-cell rate, faster just behind the head.
    uint cellId = col * 65537u + uint(row);
    float rate = mix(0.5, 3.0, unit(pcg(cellId)));
    if (behind >= 0.0 && behind < 4.0) {
        rate *= 3.0;
    }
    uint glyph = hash2(cellId, uint(floor(u.time * rate))) % uint(u.glyphCount);

    float3 color = u.color.rgb;
    if (brightness <= 0.0) {
        brightness = kBackground * unit(hash2(cellId, uint(floor(u.time * 0.5)) + 17u));
    } else if (behind == 0.0) {
        color = mix(color, float3(1.0), kHeadWhite);
        brightness = kHeadBoost;
    }

    // Sample the central 60 % of the square atlas cell so the glyph keeps its aspect ratio.
    uint atlasColumns = uint(u.atlasGrid.x);
    float2 atlasCell = float2(float(glyph % atlasColumns), float(glyph / atlasColumns));
    float2 inCell = float2(0.2 + 0.6 * local.x, local.y);
    float2 uv = (atlasCell + inCell) / u.atlasGrid;
    // Explicit LOD: derivatives jump at cell edges and would pick the wrong mip there.
    float lod = max(0.0, log2(kAtlasCell / u.cellSize.y));
    float ink = atlas.sample(s, uv, level(lod)).r;

    return float4(color * brightness * ink, 1.0);
}

fragment float4 downsampleFragment(FullscreenOut in [[stage_in]],
                                   texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    // Four bilinear taps cover the 4 × 4 source block under each destination pixel.
    float3 c = source.sample(s, in.uv + texel * float2(-1.0, -1.0)).rgb
             + source.sample(s, in.uv + texel * float2( 1.0, -1.0)).rgb
             + source.sample(s, in.uv + texel * float2(-1.0,  1.0)).rgb
             + source.sample(s, in.uv + texel * float2( 1.0,  1.0)).rgb;
    return float4(c * 0.25, 1.0);
}

fragment float4 compositeFragment(FullscreenOut in [[stage_in]],
                                  constant RainUniforms &u [[buffer(0)]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 c = base.sample(s, in.uv).rgb + bloom.sample(s, in.uv).rgb * u.bloomIntensity;
    c = 1.0 - exp(-c * kExposure);   // soft shoulder: bright heads go white instead of clipping
    return float4(c, 1.0);
}
