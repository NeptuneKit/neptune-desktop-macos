#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: smoke-test-app.sh --artifact <path> [--expected-bundle-id <id>]

Validates a packaged NeptuneDesktopMacOS .app bundle or .app.zip artifact.
Checks the app bundle structure, executable presence, Info.plist fields, and
the packaged inspector index.html file plus embedded CLI binary.

Options:
  --artifact <path>              Path to a .app bundle or .app.zip artifact
  --expected-bundle-id <id>      Optional CFBundleIdentifier to assert
  --help                         Show this help text
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd "$script_dir/.." && pwd)"
artifact_path=""
expected_bundle_id=""

resolve_path() {
  local value="$1"
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    *) printf '%s\n' "$package_root/$value" ;;
  esac
}

fail() {
  printf 'Smoke test failed: %s\n' "$1" >&2
  exit 1
}

read_plist_value() {
  local key="$1"
  local plist_path="$2"

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null || true
}

validate_app_bundle() {
  local app_path="$1"
  local contents_dir="$app_path/Contents"
  local macos_dir="$contents_dir/MacOS"
  local resources_dir="$contents_dir/Resources"
  local info_plist="$contents_dir/Info.plist"
  local inspector_index="$resources_dir/inspector/index.html"
  local embedded_cli="$resources_dir/bin/neptune"
  local bundle_identifier=""
  local bundle_executable=""
  local executable_path=""

  [[ -d "$app_path" ]] || fail "App bundle does not exist: $app_path"
  [[ "$app_path" == *.app ]] || fail "App bundle does not end with .app: $app_path"
  [[ -d "$contents_dir" ]] || fail "Missing Contents directory: $contents_dir"
  [[ -d "$macos_dir" ]] || fail "Missing MacOS directory: $macos_dir"
  [[ -d "$resources_dir" ]] || fail "Missing Resources directory: $resources_dir"
  [[ -f "$info_plist" ]] || fail "Missing Info.plist: $info_plist"
  [[ -f "$inspector_index" ]] || fail "Missing inspector index.html: $inspector_index"
  [[ -f "$embedded_cli" ]] || fail "Missing embedded CLI binary: $embedded_cli"
  [[ -x "$embedded_cli" ]] || fail "Embedded CLI binary is not executable: $embedded_cli"

  bundle_identifier="$(read_plist_value CFBundleIdentifier "$info_plist")"
  bundle_executable="$(read_plist_value CFBundleExecutable "$info_plist")"

  [[ -n "$bundle_identifier" ]] || fail "CFBundleIdentifier is missing in $info_plist"
  [[ -n "$bundle_executable" ]] || fail "CFBundleExecutable is missing in $info_plist"

  if [[ -n "$expected_bundle_id" && "$bundle_identifier" != "$expected_bundle_id" ]]; then
    fail "CFBundleIdentifier mismatch: expected $expected_bundle_id, got $bundle_identifier"
  fi

  executable_path="$macos_dir/$bundle_executable"
  [[ -f "$executable_path" ]] || fail "Executable is missing: $executable_path"
  [[ -x "$executable_path" ]] || fail "Executable is not executable: $executable_path"

  printf 'Smoke test passed: %s\n' "$app_path"
}

while (($#)); do
  case "$1" in
    --artifact)
      artifact_path="${2:-}"
      shift 2
      ;;
    --expected-bundle-id)
      expected_bundle_id="${2:-}"
      shift 2
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

if [[ -z "$artifact_path" ]]; then
  printf 'Missing required --artifact argument.\n' >&2
  usage >&2
  exit 2
fi

artifact_path="$(resolve_path "$artifact_path")"

if [[ ! -e "$artifact_path" ]]; then
  fail "Artifact does not exist: $artifact_path"
fi

if [[ -d "$artifact_path" ]]; then
  validate_app_bundle "$artifact_path"
  exit 0
fi

case "$artifact_path" in
  *.zip)
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/neptune-desktop-smoke.XXXXXX")"
    trap 'rm -rf "$temp_dir"' EXIT
    ditto -x -k "$artifact_path" "$temp_dir"

    app_bundle="$(find "$temp_dir" -maxdepth 2 -type d -name '*.app' | head -n 1)"
    [[ -n "$app_bundle" ]] || fail "No .app bundle found after extracting $artifact_path"

    validate_app_bundle "$app_bundle"
    ;;
  *)
    fail "Unsupported artifact type: $artifact_path"
    ;;
esac
