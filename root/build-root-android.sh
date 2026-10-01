#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/dist}
BUILD_MODE=${BUILD_MODE:-release}
case "$BUILD_MODE" in debug|release) ;; *) echo 'BUILD_MODE must be debug or release' >&2; exit 1 ;; esac
for tool in flutter dart python3 unzip sha256sum; do
  command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 1; }
done
cd "$SCRIPT_DIR"
if [ "${PREPARE_RUNTIME:-1}" = 1 ]; then
  python3 scripts/prepare-runtime.py
fi
for runtime in android/app/src/main/jniLibs/arm64-v8a/libmihomo.so \
  android/app/src/main/assets/geodata/geosite.dat \
  android/app/src/main/assets/geodata/geoip.dat \
  android/app/src/main/assets/geodata/country.mmdb; do
  [ -s "$runtime" ] || { echo "Missing runtime: $runtime" >&2; exit 1; }
done
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
# Flutter creates the local SDK properties before Gradle unit tests run.
flutter build apk "--$BUILD_MODE" --target-platform android-arm64
(cd android && ./gradlew :app:testDebugUnitTest)
version=$(sed -n 's/^version: *//p' pubspec.yaml)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || { echo 'Invalid pubspec version' >&2; exit 1; }
apk="build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
unzip -t "$apk" >/dev/null
if [ "$BUILD_MODE" = release ]; then
  sdk_dir=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
  if [ -z "$sdk_dir" ]; then
    sdk_dir=$(sed -n 's/^sdk.dir=//p' android/local.properties)
  fi
  signer=$(python3 - "$sdk_dir" <<'PY_SIGNER'
import pathlib, sys
sdk = pathlib.Path(sys.argv[1])
tools = list((sdk / "build-tools").glob("*/apksigner"))
if not tools:
    raise SystemExit("Android SDK apksigner not found")
print(max(tools, key=lambda p: tuple(int(x) for x in p.parent.name.split('.') if x.isdigit())))
PY_SIGNER
)
  "$signer" verify --verbose "$apk"
fi
unzip -l "$apk" | awk '/lib\/arm64-v8a\/libmihomo.so/ {found=1} END {exit !found}'
mkdir -p "$OUTPUT_DIR"
dest="$OUTPUT_DIR/Mclash-root-android-$version-arm64-v8a-$BUILD_MODE.apk"
cp "$apk" "$dest"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$dest")" > "$(basename "$dest").sha256")
echo "Build complete: $dest"
