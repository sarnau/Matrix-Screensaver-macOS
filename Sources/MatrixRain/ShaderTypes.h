#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/// Per-frame constants for every fragment shader. Shared by Swift and MSL so the layout cannot drift.
/// 64 bytes, 16-byte aligned.
typedef struct {
    simd_float4 color;       // rain colour, linear RGB (w unused)
    simd_float2 resolution;  // drawable size, pixels
    simd_float2 cellSize;    // grid cell size, pixels
    simd_float2 grid;        // columns, rows
    simd_float2 atlasGrid;   // glyph atlas columns, rows
    float time;              // seconds since start, wrapped
    float speed;             // fall speed multiplier
    float glyphCount;        // glyphs in the atlas
    float bloomIntensity;    // 0 disables bloom
} RainUniforms;

#endif
