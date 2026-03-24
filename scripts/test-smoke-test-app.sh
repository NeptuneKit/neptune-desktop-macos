#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
smoke_script="$script_dir/smoke-test-app.sh"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/neptune-desktop-smoke-test.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT

fake_app="$temp_root/NeptuneDesktopMacOS.app"
contents_dir="$fake_app/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources/inspector"
executable_name="NeptuneDesktopMacOS"
bundle_identifier="com.neptunekit.neptune-desktop-macos"

mkdir -p "$macos_dir" "$resources_dir"

cat >"$macos_dir/$executable_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$macos_dir/$executable_name"

cat >"$contents_dir/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$executable_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_identifier</string>
</dict>
</plist>
EOF

cat >"$resources_dir/index.html" <<'EOF'
<!doctype html>
<html>
  <body>Inspector</body>
</html>
EOF

"$smoke_script" --artifact "$fake_app" --expected-bundle-id "$bundle_identifier"

zip_path="$temp_root/NeptuneDesktopMacOS.app.zip"
ditto -c -k --keepParent "$fake_app" "$zip_path"
"$smoke_script" --artifact "$zip_path" --expected-bundle-id "$bundle_identifier"

printf 'Smoke test script validation passed.\n'
