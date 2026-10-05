# Matrix Rain Screensaver — Design

Date: 2026-10-06
Status: Draft for review

## Goal

A macOS screensaver module (`MatrixRain.saver`) written in Swift that renders a
film-accurate "digital rain" effect with Metal. Personal use: built in Xcode,
signed with an Apple Development identity, installed by double-clicking. No
notarization.

## Requirements

- macOS 14 Sonoma or later; universal binary (`arm64` + `x86_64`).
- Film-accurate look: mirrored half-width katakana + digits + a few symbols,
  bright white-tinted leading glyph, fading trails, glyphs that mutate in
  place, soft bloom.
- Works full-screen on every attached display (each display runs its own
  instance at its own refresh rate) and in the System Settings preview
  thumbnail.
- Options sheet with: fall speed, density, colour, bloom on/off. Changes apply
  live and persist.
- Must never crash or hang the `legacyScreenSaver` host, and must stop using
  the GPU once the screensaver is dismissed.
- Builds without warnings under Swift 6 strict concurrency.

## Non-goals

- Notarization / Developer ID distribution.
- 3D depth, camera motion, or interactive/reactive effects.
- Selectable glyph sets, frame-rate caps, spanning rain across displays.

## Approach

Procedural rendering: a full-screen fragment shader computes every cell's
state as a pure function of `(column, row, time)` using hash functions. The CPU
holds no per-cell simulation state; per frame it uploads only a small uniforms
struct. Glyph shapes come from a texture atlas rasterised once with CoreText.
Bloom is a downsample → MPS Gaussian blur → additive composite.

Rejected alternatives: CPU simulation with instanced quads (more code, CPU cost
per display), GPU compute simulation with state textures (complexity without a
need).

## Project layout

Generated with XcodeGen from `project.yml`.

Targets:

- `MatrixRain` — Screen Saver bundle (`.saver`), `NSPrincipalClass =
  MatrixRainView`. Bundle ID `com.sarnau.MatrixRain`.
- `MatrixRainHost` — small macOS app that embeds `MatrixRainView` in a
  resizable window, for running and GPU-debugging outside `legacyScreenSaver`.
  Compiles the same sources (not by loading the bundle).
- `MatrixRainTests` — XCTest unit tests, hosted by `MatrixRainHost`.

Source files (`Sources/MatrixRain/`):

| File | Responsibility | Depends on |
|---|---|---|
| `MatrixRainView.swift` | `ScreenSaverView` subclass; owns `CAMetalLayer`, display link, preview handling, configure sheet hookup, stop notification. | Renderer, Settings, ConfigureSheet |
| `Renderer.swift` | Metal device/queue/pipelines, offscreen textures, per-frame encode (rain → bloom → composite). API: `init?(device:layer:bundle:settings:)`, `resize(drawableSize:scale:)`, `update(settings:)`, `draw(time:)`, plus `encodeFrame(into:time:)` for tests. | GlyphAtlas, Settings, ShaderTypes |
| `GlyphAtlas.swift` | Rasterises the glyph set via CoreText into an `MTLTexture`; exposes glyph count and atlas grid dimensions. | CoreText, Metal |
| `Shaders.metal` | `fullscreenVertex`, `rainFragment`, `downsampleFragment`, `compositeFragment`. | ShaderTypes.h |
| `ShaderTypes.h` | C struct `RainUniforms`, shared by Swift (bridging header) and MSL. | — |
| `Settings.swift` | Value type: `speed`, `density`, `color` (RGB), `bloom`. Load/save via `ScreenSaverDefaults`, clamped, with defaults. | ScreenSaver |
| `ConfigureSheet.swift` | Programmatic AppKit sheet: 2 sliders, `NSColorWell`, checkbox, OK/Cancel. | Settings |
| `GridMetrics.swift` | Pure functions: cell size in pixels and column/row counts from view size, backing scale, and density. | — |

## Rendering

### Grid

Base cell height 22 pt at density 1.0; cell height in points = `22 / density`;
cell width = 0.6 × height. Pixel sizes multiply by `backingScaleFactor`.
`columns = ceil(widthPx / cellW)`, `rows = ceil(heightPx / cellH)`. In preview
mode the base cell height is scaled down so the thumbnail shows a comparable
number of columns.

### Uniforms (`RainUniforms`)

`time` (float), `speed` (float), `resolution` (float2, pixels),
`cellSize` (float2, pixels), `grid` (float2, columns/rows), `color` (float3,
linear), `atlasGrid` (float2), `glyphCount` (float), `bloomEnabled` (float),
`bloomIntensity` (float).

### Rain pass — `rainFragment`

Output: offscreen `rgba16Float` texture at drawable size.

Per pixel:

1. `cell = floor(pos / cellSize)`, `local = fract(pos / cellSize)`.
2. Per column hash → speed multiplier in [0.6, 1.4], phase, trail length in
   [0.3, 0.9] of screen height. Two independent drops per column (second with
   different hash seed); take the max brightness.
3. Distance behind head: `d = fract((time·speed·colSpeed + phase) − row/rows)`
   in screen-height units. Trail brightness `b = pow(saturate(1 − d/len), 2)`.
   Background residual: cells outside trails get ~0.03 brightness flicker.
4. Head cell (`d < 1/rows`): brightness 1.8, colour blended 70% toward white.
5. Glyph index = `hash(col, row, floor(time · rate))` mod glyphCount, where
   `rate` is per-cell in [0.5, 3] Hz, ×3 within the first few cells behind
   the head.
6. Sample atlas at that glyph's sub-rect using `local` (with padding);
   output `colour · b · glyphAlpha` in linear space.

### Glyph atlas

72 glyphs: the 56 half-width katakana U+FF66–U+FF9D, the 10 digits `0–9`,
and 6 symbols `: . = * + -`. Font: Hiragino Sans W3 (`HiraginoSans-W3`);
fallback Menlo with the digits, symbols and `A–Z` (also padded to 72 by
repetition). Each glyph is rendered mirrored horizontally, centred in a
64×64 px cell with padding, into an 8-column × 9-row grid → 512×576 `r8Unorm`
texture with mipmaps generated by a blit
encoder. Sampler: linear min/mag, linear mip.

### Bloom

When enabled: `downsampleFragment` renders the rain texture into a ¼-resolution
`rgba16Float` texture, `MPSImageGaussianBlur` (σ = 6) blurs it into a second
¼-res texture. When disabled, these passes are skipped.

### Composite — `compositeFragment`

`c = base + bloom · bloomIntensity (0.8)`; tone map `1 − exp(−c)`; write to the
drawable (`bgra8Unorm_srgb`).

## Lifecycle

- `init(frame:isPreview:)`: configure layer-backed view with a `CAMetalLayer`,
  load Settings, create Renderer. If Renderer creation fails, log via `os_log`
  and enter fallback mode (fill black in `draw(_:)`, no display link).
- `startAnimation` / `viewDidMoveToWindow` (non-nil window): create
  `NSView.displayLink(target:selector:)` and add to the main run loop. Each
  tick: `renderer.draw(time:)` using time since start, wrapped modulo 10 000 s.
- `stopAnimation`, `viewDidMoveToWindow` with nil window, and the distributed
  notification `com.apple.screensaver.willstop`: invalidate the display link.
  All paths idempotent.
- `setFrameSize` / backing-property change: update layer `drawableSize` and
  `contentsScale`, call `renderer.resize`.
- `animateOneFrame` is not used for rendering.
- All Metal resources are loaded with `Bundle(for: MatrixRainView.self)`;
  the metallib via `device.makeDefaultLibrary(bundle:)`.

## Options sheet

| Control | Range | Default |
|---|---|---|
| Fall speed slider | 0.25 – 3.0 | 1.0 |
| Density slider | 0.5 – 2.0 | 1.0 |
| Colour well | any sRGB | `#00FF41` |
| Bloom checkbox | on/off | on |

`hasConfigureSheet = true`; `configureSheet` returns the window. OK: save,
`synchronize()`, apply to the renderer, end sheet. Cancel: discard edits, end
sheet. Defaults module name = bundle identifier. Missing or out-of-range values
fall back to defaults / are clamped.

## Error handling

- No `fatalError` and no force-unwraps on Metal or CoreText objects.
- Setup failures are logged (subsystem `com.sarnau.MatrixRain`) and result in a
  black screen, never a crash.
- Per-frame failures (no drawable, no command buffer) skip the frame.

## Testing

Unit tests (`MatrixRainTests`):

- `Settings`: save/load round trip; clamping of out-of-range values; defaults
  when keys are absent.
- `GridMetrics`: column/row counts for several sizes, scales, densities.
- `GlyphAtlas`: builds; texture is 512×576; glyph count is 72.
- `Renderer`: encode one frame at t = 5 s into an offscreen texture; read back
  and assert some pixels are non-black and the green channel dominates.

Manual verification:

- Run `MatrixRainHost` and inspect the effect; toggle bloom; resize the window.
- Install the `.saver`, check System Settings thumbnail and options sheet, run
  full-screen on all displays.
- After dismissing, confirm in Activity Monitor that `legacyScreenSaver` GPU
  usage drops to zero.

Build: `xcodebuild` for both targets, no warnings, Swift 6 language mode.
