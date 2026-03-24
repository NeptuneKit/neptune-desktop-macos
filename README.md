# neptune-desktop-macos

NeptuneKit v2 macOS shell app.

## What it does

- Launches a minimal AppKit window.
- Embeds `WKWebView` and resolves inspector assets in this order: `NEPTUNE_INSPECTOR_DIST`, `../neptune-inspector-h5/dist`, packaged app resources at `Resources/inspector/index.html`, then `http://127.0.0.1:18765/`.
- Falls back to `http://127.0.0.1:18765/` when no local inspector asset is present.
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

The window will first look for a local inspector asset, then fall back to `http://127.0.0.1:18765/`.

## CI

GitHub Actions runs on every `push` to `main` and on every `pull_request`. The workflow uses `swift build` followed by `swift test` on `macos-15` to keep the package and test suite validated continuously.

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

- Copy the built inspector dist into the app bundle at `Resources/inspector/` for release packaging.
- Wire a packaging step in CI/release scripts so bundle resources stay in sync with the inspector build output.

## Notes

- This is intentionally a thin shell. Static asset loading already works for local dist folders and packaged app resources; release packaging still needs a copy step to move built inspector files into `Resources/inspector/`.
- `.build/` and `.swiftpm/` are ignored so local builds do not dirty the repo.
