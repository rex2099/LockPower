#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/build"
app_dir="$build_dir/LockPower.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
plist_file="$contents_dir/Info.plist"

/bin/mkdir -p "$build_dir" "$macos_dir"
/usr/bin/clang \
    -fobjc-arc \
    -O2 \
    -framework AppKit \
    -framework CoreGraphics \
    "$script_dir/Sources/LockPower/main.m" \
    -o "$build_dir/LockPower"

/usr/bin/install -m 0755 "$build_dir/LockPower" "$macos_dir/LockPower"
/usr/bin/plutil -create xml1 "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDevelopmentRegion string en' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string LockPower' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.lockpower' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string LockPower' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.2.0' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 2' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$plist_file"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist_file"
/usr/bin/plutil -lint "$plist_file"
/usr/bin/codesign --force --sign - "$app_dir"

echo "Built $build_dir/LockPower"
echo "Built $app_dir"
