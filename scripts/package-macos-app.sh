#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: package-macos-app.sh [options]

Builds NeptuneDesktopMacOS with SwiftPM and assembles a distributable .app bundle.
Copies the inspector dist into both the app bundle Resources/inspector directory
and the SwiftPM resource bundle used by Bundle.module.

Options:
  --configuration <Debug|Release>  Swift build configuration (default: Release)
  --dist <path>                    Path to neptune-inspector-h5/dist
  --gateway-bin <path>             Path to neptune CLI binary to embed into app resources
  --output <path>                  Output .app bundle path (default: .build/artifacts/NeptuneDesktopMacOS.app)
  --bundle-id <id>                 CFBundleIdentifier to write into Info.plist
  --dry-run                        Print planned actions without writing files
  --help                           Show this help text
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd "$script_dir/.." && pwd)"
default_dist_path="../neptune-inspector-h5/dist"
default_output_path=".build/artifacts/NeptuneDesktopMacOS.app"
configuration="Release"
dist_path="$default_dist_path"
output_path="$default_output_path"
bundle_identifier="com.neptunekit.neptune-desktop-macos"
gateway_bin_path=""
dry_run=false

resolve_path() {
  local value="$1"
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    *) printf '%s\n' "$package_root/$value" ;;
  esac
}

run() {
  if $dry_run; then
    printf '[dry-run]'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

while (($#)); do
  case "$1" in
    --configuration)
      configuration="${2:-}"
      shift 2
      ;;
    --dist)
      dist_path="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    --gateway-bin)
      gateway_bin_path="${2:-}"
      shift 2
      ;;
    --bundle-id)
      bundle_identifier="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$configuration" || -z "$dist_path" || -z "$output_path" || -z "$bundle_identifier" ]]; then
  printf 'Missing required argument value.\n' >&2
  usage >&2
  exit 2
fi

swift_configuration="$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')"

dist_path="$(resolve_path "$dist_path")"
output_path="$(resolve_path "$output_path")"
if [[ -n "$gateway_bin_path" ]]; then
  gateway_bin_path="$(resolve_path "$gateway_bin_path")"
fi

binary_name="NeptuneDesktopMacOS"
gateway_binary_name="neptune"
bundle_name="NeptuneDesktopMacOS_NeptuneDesktopMacOS.bundle"
bundle_dir="$(dirname "$output_path")/$bundle_name"
top_level_resources_dir="$output_path/Contents/Resources"
top_level_inspector_dir="$top_level_resources_dir/inspector"
top_level_gateway_bin_dir="$top_level_resources_dir/bin"
bundle_inspector_dir="$bundle_dir/Contents/Resources/inspector"

if [[ "$dry_run" == false ]]; then
  if [[ ! -d "$dist_path" ]]; then
    printf 'Inspector dist directory does not exist: %s\n' "$dist_path" >&2
    exit 1
  fi
fi

cd "$package_root"

run swift build -c "$swift_configuration" --product "$binary_name"
bin_path="$(swift build -c "$swift_configuration" --show-bin-path)"
binary_path="$bin_path/$binary_name"
resource_bundle_source="$bin_path/$bundle_name"

if [[ -z "$gateway_bin_path" ]]; then
  if command -v "$gateway_binary_name" >/dev/null 2>&1; then
    gateway_bin_path="$(command -v "$gateway_binary_name")"
  fi
fi

if [[ "$dry_run" == false ]]; then
  if [[ ! -x "$binary_path" ]]; then
    printf 'Built executable not found: %s\n' "$binary_path" >&2
    exit 1
  fi
  if [[ ! -d "$resource_bundle_source" ]]; then
    printf 'SwiftPM resource bundle not found: %s\n' "$resource_bundle_source" >&2
    exit 1
  fi
  if [[ -z "$gateway_bin_path" ]]; then
    printf 'Embedded CLI binary not found. Set --gateway-bin or make `%s` available on PATH.\n' "$gateway_binary_name" >&2
    exit 1
  fi
  if [[ ! -x "$gateway_bin_path" ]]; then
    printf 'Embedded CLI binary is not executable: %s\n' "$gateway_bin_path" >&2
    exit 1
  fi
fi

run rm -rf "$output_path" "$bundle_dir"
run mkdir -p "$(dirname "$output_path")"
run mkdir -p "$output_path/Contents/MacOS"
run mkdir -p "$top_level_inspector_dir"
run mkdir -p "$top_level_gateway_bin_dir"
run ditto "$resource_bundle_source" "$bundle_dir"
run ditto "$dist_path" "$top_level_inspector_dir"
run ditto "$dist_path" "$bundle_inspector_dir"
run cp "$binary_path" "$output_path/Contents/MacOS/$binary_name"
run cp "$gateway_bin_path" "$top_level_gateway_bin_dir/$gateway_binary_name"
run chmod +x "$top_level_gateway_bin_dir/$gateway_binary_name"

if $dry_run; then
  printf '[dry-run] write %q\n' "$output_path/Contents/Info.plist"
else
  mkdir -p "$output_path/Contents"
  cat >"$output_path/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$binary_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_identifier</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$binary_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF
fi

printf 'Packaged app: %s\n' "$output_path"
