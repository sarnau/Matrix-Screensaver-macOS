# Matrix Rain

A macOS 14+ screensaver that renders film-style Matrix digital rain with Metal.

## Build and install

Requires Xcode 16+ with the Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`)
and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
Scripts/install.sh
```

Then pick **Matrix Rain** in System Settings → Screen Saver. **Options…** sets fall speed, density, colour, and glow.

## Develop

```bash
xcodegen generate
open MatrixRain.xcodeproj
```

- Run the **MatrixRainHost** scheme to see the effect in a window (⌘, opens the options sheet). Use it for the Metal frame debugger.
- Tests: `xcodebuild test -project MatrixRain.xcodeproj -scheme MatrixRainHost -destination 'platform=macOS'`
- Logs: `log stream --predicate 'subsystem == "com.sarnau.MatrixRain"'`

The project file is generated from `project.yml`; edit that, not the `.xcodeproj`.

Design: `docs/superpowers/specs/2026-10-06-matrix-screensaver-design.md`.
