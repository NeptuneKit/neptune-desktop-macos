# neptune-desktop-macos

NeptuneKit v2 macOS shell app.

## What it does

- Launches a minimal AppKit window.
- Embeds `WKWebView` and loads `http://127.0.0.1:18765/` by default.
- Launches `neptune-gateway` automatically when the shell starts.

## Current structure

- `Sources/NeptuneDesktopMacOS/main.swift`: app entry and lifecycle.
- `Sources/NeptuneDesktopMacOS/WindowController.swift`: window + `WKWebView` host.
- `Sources/NeptuneDesktopMacOS/GatewayLauncher.swift`: gateway process launcher.

## Run locally

```bash
swift build
swift run NeptuneDesktopMacOS
```

The window will attempt to load the local gateway at `http://127.0.0.1:18765/`.

## Gateway launch

The app tries to launch `neptune-gateway` automatically when it starts.

You can override the binary path and network binding with environment variables:

- `NEPTUNE_GATEWAY_BIN`: absolute path to the gateway binary, or a command name on `PATH`
- `NEPTUNE_HOST`: gateway bind host, default `127.0.0.1`
- `NEPTUNE_PORT`: gateway bind port, default `18765`

Example:

```bash
export NEPTUNE_GATEWAY_BIN=/path/to/neptune-gateway
export NEPTUNE_HOST=127.0.0.1
export NEPTUNE_PORT=18765
swift run NeptuneDesktopMacOS
```

If the gateway fails to start, the window still opens and the error is printed to the console.

## Local workflow

1. Build and place the gateway binary somewhere on `PATH`, or point `NEPTUNE_GATEWAY_BIN` to it.
2. Start this desktop shell.
3. The embedded `WKWebView` loads the gateway at `http://127.0.0.1:18765/`.

## Next integration points

- Bundle static assets from `neptune-inspector-h5` into the app.
- Replace the default URL with a packaged local file URL when the inspector build output is wired in.

## Notes

- This is intentionally a thin shell. The static asset pipeline is left as an explicit TODO.
- `.build/` and `.swiftpm/` are ignored so local builds do not dirty the repo.
