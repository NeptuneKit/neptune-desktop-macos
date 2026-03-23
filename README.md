# neptune-desktop-macos

NeptuneKit v2 macOS shell app.

## What it does

- Launches a minimal AppKit window.
- Embeds `WKWebView` and prefers a local packaged inspector `dist/index.html` when available.
- Falls back to `http://127.0.0.1:18765/` when no local inspector build output is present.
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

The window will first look for a local inspector build output, then fall back to `http://127.0.0.1:18765/`.

## Inspector 资源加载

默认情况下，desktop app 会按以下顺序查找 inspector 静态资源：

1. `NEPTUNE_INSPECTOR_DIST` 指定的目录
2. `../neptune-inspector-h5/dist`，相对于 `neptune-desktop-macos` 仓库目录
3. `http://127.0.0.1:18765/`

只要目录下存在 `index.html`，就会以本地文件方式打开，并允许 `dist/` 目录内的静态资源读取。

示例：

```bash
export NEPTUNE_INSPECTOR_DIST=/absolute/path/to/neptune-inspector-h5/dist
swift run NeptuneDesktopMacOS
```

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
2. Build the inspector with `npm run build` inside `neptune-inspector-h5`, or point `NEPTUNE_INSPECTOR_DIST` to an existing `dist/` directory.
3. Start this desktop shell.
4. The embedded `WKWebView` loads the local inspector first, otherwise it falls back to the gateway URL.

## Next integration points

- Bundle the inspector dist into the app bundle for release packaging.
- Add a dedicated packaged-resources search path when we introduce app bundle resources.

## Notes

- This is intentionally a thin shell. The static asset pipeline is left as an explicit TODO.
- `.build/` and `.swiftpm/` are ignored so local builds do not dirty the repo.
