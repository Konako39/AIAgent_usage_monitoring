#!/bin/zsh
set -euo pipefail

project_root=${0:A:h}
dist_dir="$project_root/dist"
asset_work=$(mktemp -d)
trap 'rm -rf "$asset_work"' EXIT

swift build -c release --package-path "$project_root"
swiftc "$project_root/Tools/IconGenerator.swift" -o "$asset_work/IconGenerator"
"$asset_work/IconGenerator" "$asset_work/icon-1024.png"

iconset="$asset_work/AppIcon.iconset"
mkdir -p "$iconset" "$dist_dir"
sips -z 16 16 "$asset_work/icon-1024.png" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$asset_work/icon-1024.png" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$asset_work/icon-1024.png" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$asset_work/icon-1024.png" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$asset_work/icon-1024.png" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$asset_work/icon-1024.png" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$asset_work/icon-1024.png" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$asset_work/icon-1024.png" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$asset_work/icon-1024.png" --out "$iconset/icon_512x512.png" >/dev/null
cp "$asset_work/icon-1024.png" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$asset_work/AppIcon.icns"

app_path="$dist_dir/Agent AI Usage.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_root/.build/release/QuotaMonitor" "$app_path/Contents/MacOS/QuotaMonitor"
cp "$project_root/Info.plist" "$app_path/Contents/Info.plist"
cp "$asset_work/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
cp "$project_root/Sources/QuotaMonitor/Resources/openai.png" "$app_path/Contents/Resources/openai.png"
cp "$project_root/Sources/QuotaMonitor/Resources/claude.png" "$app_path/Contents/Resources/claude.png"
chmod +x "$app_path/Contents/MacOS/QuotaMonitor"
codesign --force --deep --sign - "$app_path" >/dev/null

echo "Built: $app_path"
