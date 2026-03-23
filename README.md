# neptune-desktop-macos

NeptuneKit v2 macOS shell app.

## What it does

- Launches a minimal AppKit window.
- Embeds `WKWebView` and loads `http://127.0.0.1:18765/` by default.
- Reserves a `GatewayLauncher` slot for wiring `neptune-gateway-swift` later.

## Current structure

- `Sources/NeptuneDesktopMacOS/main.swift`: app entry and lifecycle.
- `Sources/NeptuneDesktopMacOS/WindowController.swift`: window + `WKWebView` host.
- `Sources/NeptuneDesktopMacOS/GatewayLauncher.swift`: gateway launch placeholder.

## Run locally

```bash
swift build
swift run NeptuneDesktopMacOS
```

The window will attempt to load the local gateway at `http://127.0.0.1:18765/`.

## Next integration points

- Embed or launch `neptune-gateway-swift` from `GatewayLauncher`.
- Bundle static assets from `neptune-inspector-h5` into the app.
- Replace the default URL with a packaged local file URL when the inspector build output is wired in.

## Notes

- This is intentionally a thin shell. The gateway lifecycle and static asset pipeline are left as explicit TODOs.
- `.build/` and `.swiftpm/` are ignored so local builds do not dirty the repo.
