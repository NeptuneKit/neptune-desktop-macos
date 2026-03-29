# neptune-desktop-macos

NeptuneKit v2 macOS shell app.

## What it does

- Launches a minimal AppKit window as a CLI shell.
- Starts and stops `neptune` (CLI) lifecycle.
- Shows a Web URL for opening Inspector in an external browser.
- Streams CLI `stdout` / `stderr` logs into the desktop window.

## Current structure

- `Sources/NeptuneDesktopMacOS/main.swift`: app entry and lifecycle.
- `Sources/NeptuneDesktopMacOS/WindowController.swift`: window + CLI control panel + log console.
- `Sources/NeptuneDesktopMacOS/GatewayLauncher.swift`: gateway process launcher.
- `Sources/NeptuneDesktopMacOS/DesktopRuntimeConfiguration.swift`: runtime configuration resolver.

## Run locally

```bash
swift build
swift run NeptuneDesktopMacOS
```

The window will first look for a local inspector asset, then fall back to `http://127.0.0.1:18765/`.

## CI

GitHub Actions runs on every `push` to `main` and on every `pull_request`. The workflow uses `swift build` followed by `swift test` on `macos-15` to keep the package and test suite validated continuously.

## Web URL 展示

桌面端不再内嵌 Inspector 页面，而是展示可访问 URL，并提供：

1. 一键复制 URL
2. 一键用默认浏览器打开

Web URL 解析优先级：

1. `NEPTUNE_WEB_URL`
2. `NEPTUNE_INSPECTOR_URL`（兼容旧变量）
3. `http://<NEPTUNE_HOST>:<NEPTUNE_PORT>/`

## Gateway launch

The app tries to launch `neptune` automatically when it starts.
Binary resolution priority:
1. `NEPTUNE_GATEWAY_BIN`（显式覆盖）
2. packaged `.app` 内置 `Contents/Resources/bin/neptune`
3. 仓库内托管构建产物 `../neptune-gateway-swift/.build/*/neptune`
4. `PATH` 中的 `neptune`（最后兜底）

You can override the binary path and network binding with environment variables:

- `NEPTUNE_GATEWAY_BIN`: absolute path to the gateway binary, or a command name on `PATH`
- `NEPTUNE_HOST`: gateway bind host, default `127.0.0.1`
- `NEPTUNE_PORT`: gateway bind port, default `18765`
- `NEPTUNE_WEB_URL`: override displayed inspector web URL
- `NEPTUNE_INSPECTOR_URL`: legacy URL override (still supported)

Example:

```bash
export NEPTUNE_GATEWAY_BIN=/path/to/neptune
export NEPTUNE_HOST=127.0.0.1
export NEPTUNE_PORT=18765
swift run NeptuneDesktopMacOS
```

If the gateway fails to start, the window still opens and the error is printed to the console.

## Release packaging

Use the packaging script to build a distributable macOS app bundle and copy the inspector dist into the bundle resources:

```bash
./scripts/package-macos-app.sh \
  --dist ../neptune-inspector-h5/dist \
  --output .build/artifacts/NeptuneDesktopMacOS.app
```

The script runs `swift build`, assembles `NeptuneDesktopMacOS.app`, copies the SwiftPM resource bundle, and places the inspector dist under both the app bundle `Resources/inspector/` path and the SwiftPM resource bundle used by `Bundle.module`.
It also embeds the `neptune` CLI into `Contents/Resources/bin/neptune` (from `--gateway-bin` or current `PATH`).

### Smoke test

发布流程会在 `zip` 前后运行 `scripts/smoke-test-app.sh`，确保打包产物满足最小可运行结构：

- `.app` bundle 结构存在
- `Contents/MacOS/<executable>` 可执行文件存在
- `Contents/Info.plist` 中的 `CFBundleIdentifier` 和 `CFBundleExecutable` 可读
- `Contents/Resources/inspector/index.html` 存在
- `Contents/Resources/bin/neptune` 存在且可执行

脚本也可以本地复用：

```bash
./scripts/smoke-test-app.sh \
  --artifact .build/artifacts/NeptuneDesktopMacOS.app \
  --expected-bundle-id com.neptunekit.neptune-desktop-macos

./scripts/smoke-test-app.sh \
  --artifact .build/artifacts/NeptuneDesktopMacOS.app.zip \
  --expected-bundle-id com.neptunekit.neptune-desktop-macos
```

脚本的最小自动化验证位于 `scripts/test-smoke-test-app.sh`，会生成一个临时假 `.app` 和 `.app.zip` 并执行 smoke test。

## GitHub Actions 打包与发布

仓库提供了两个 macOS 分发 workflow：

1. 打开 GitHub Actions。
2. 选择 `Package Desktop App`。
3. 点击 `Run workflow`，可选选择 `Release` 或 `Debug`。
4. Workflow 会先 checkout 当前仓库，再 checkout `NeptuneKit/neptune-inspector-h5` 到相邻目录。
5. 先执行 `./scripts/build-desktop-assets.sh`，再执行 `./scripts/package-macos-app.sh`。
6. 最终上传 `NeptuneDesktopMacOS.app.zip` 作为 artifact，文件名与打包产物保持一致。

Release workflow 适合正式发布：

1. 推送 `v*` tag 时会自动执行 `Release Desktop App`。
2. 也可以手动触发 `workflow_dispatch`，并在 `tag_name` 中指定要发布的 tag。
3. Workflow 会复用同样的打包逻辑，生成 `NeptuneDesktopMacOS.app.zip` 后通过 `softprops/action-gh-release` 发布到 GitHub Release。
4. 手动触发时还可以选择 `draft` 和 `prerelease`。

如果需要本地复现，步骤与 workflow 相同，只是直接运行两个脚本：

```bash
cd neptune-inspector-h5
./scripts/build-desktop-assets.sh

cd ../neptune-desktop-macos
./scripts/package-macos-app.sh \
  --configuration Release \
  --dist ../neptune-inspector-h5/dist \
  --output .build/artifacts/NeptuneDesktopMacOS.app
```

## Notes

- This is intentionally a thin shell. Static asset loading already works for local dist folders and packaged app resources.
- `.build/` and `.swiftpm/` are ignored so local builds do not dirty the repo.
