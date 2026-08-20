#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR=${1:-$SCRIPT_DIR}
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/dist}
BUILD_MODE=${BUILD_MODE:-release}
ABI=arm64-v8a

cleanup_build_files() {
  rm -rf \
    "$SOURCE_DIR/build" \
    "$SOURCE_DIR/.dart_tool" \
    "$SOURCE_DIR/.pub" \
    "$SOURCE_DIR/android/.gradle" \
    "$SOURCE_DIR/android/.kotlin"
  rm -f \
    "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI/libmihomo.so" \
    "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI/libhev-socks5-tunnel.so" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata/geosite.dat" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata/geoip.dat" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata/country.mmdb"
  rmdir \
    "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI" \
    "$SOURCE_DIR/android/app/src/main/jniLibs" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata" \
    2>/dev/null || true
}
trap cleanup_build_files EXIT

case "$BUILD_MODE" in
  debug|release) ;;
  *) echo "BUILD_MODE 只能是 debug 或 release" >&2; exit 1 ;;
esac

for command_name in flutter dart unzip sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "缺少必需命令：$command_name" >&2
    exit 1
  }
done

[ -f "$SOURCE_DIR/pubspec.yaml" ] || {
  echo "源码目录无效：$SOURCE_DIR" >&2
  exit 1
}

required_runtime_files=(
  "android/app/src/main/jniLibs/$ABI/libmihomo.so"
  "android/app/src/main/jniLibs/$ABI/libhev-socks5-tunnel.so"
  "android/app/src/main/assets/geodata/geosite.dat"
  "android/app/src/main/assets/geodata/geoip.dat"
  "android/app/src/main/assets/geodata/country.mmdb"
)
for required_file in "${required_runtime_files[@]}"; do
  [ -s "$SOURCE_DIR/$required_file" ] || {
    echo "缺少 Android 运行资源：$SOURCE_DIR/$required_file" >&2
    exit 1
  }
done

mkdir -p "$OUTPUT_DIR"
cd "$SOURCE_DIR"
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk "--$BUILD_MODE" --target-platform android-arm64

APK="$SOURCE_DIR/build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
[ -f "$APK" ] || { echo "Android APK 未生成" >&2; exit 1; }
unzip -t "$APK" >/dev/null

DEST="$OUTPUT_DIR/Mclash-android-$ABI-$BUILD_MODE.apk"
cp "$APK" "$DEST"
sha256sum "$DEST" > "$DEST.sha256"
echo "构建完成：$DEST"
