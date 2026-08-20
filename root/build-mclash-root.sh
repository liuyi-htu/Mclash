#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR=${1:-$SCRIPT_DIR}
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/dist}
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
    "$SOURCE_DIR/android/app/src/main/assets/geodata/geosite.dat" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata/geoip.dat" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata/country.mmdb" \
    "$OUTPUT_DIR/mclash_root.zip"
  rmdir \
    "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI" \
    "$SOURCE_DIR/android/app/src/main/jniLibs" \
    "$SOURCE_DIR/android/app/src/main/assets/geodata" \
    2>/dev/null || true
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup_build_files EXIT

for command_name in curl gzip sha256sum unzip java flutter python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "缺少必需命令：$command_name" >&2
    exit 1
  }
done

[ -f "$SOURCE_DIR/pubspec.yaml" ] || {
  echo "源码目录无效：$SOURCE_DIR" >&2
  exit 1
}
if [ -f "$SOURCE_DIR/key.properties" ]; then
  STORE_FILE_VALUE=$(sed -n 's/^storeFile=//p' "$SOURCE_DIR/key.properties" | tail -n 1)
  [ -n "$STORE_FILE_VALUE" ] || { echo "key.properties 缺少 storeFile" >&2; exit 1; }
  case "$STORE_FILE_VALUE" in
    /*) KEYSTORE_PATH=$STORE_FILE_VALUE ;;
    *) KEYSTORE_PATH=$SOURCE_DIR/$STORE_FILE_VALUE ;;
  esac
  [ -f "$KEYSTORE_PATH" ] || { echo "签名文件不存在：$KEYSTORE_PATH" >&2; exit 1; }
  sed "s|^storeFile=.*|storeFile=$KEYSTORE_PATH|" "$SOURCE_DIR/key.properties" \
    > "$SOURCE_DIR/android/key.properties"
fi
[ -f "$SOURCE_DIR/android/key.properties" ] || [ -n "${MCLASH_STORE_FILE:-}" ] || {
  echo "缺少 android/key.properties；Release 必须使用正式签名" >&2
  exit 1
}

mkdir -p "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI"
mkdir -p "$SOURCE_DIR/android/app/src/main/assets/geodata" "$OUTPUT_DIR"
rm -f \
  "$OUTPUT_DIR/mihomo-android-arm64-v8.gz" \
  "$OUTPUT_DIR/mihomo-manifest-arm64-v8a.json"
WORK_DIR=$(mktemp -d)

asset_url() {
  repository=$1
  pattern=$2
  api_headers=(
    -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28'
    -H 'User-Agent: Mclash-GitHub-Build'
  )
  if [ -n "${GH_TOKEN:-}" ]; then
    api_headers+=(-H "Authorization: Bearer $GH_TOKEN")
  fi
  curl -fsSL --retry 3 "${api_headers[@]}" \
    "https://api.github.com/repos/$repository/releases/latest" |
    python3 -c 'import json,re,sys
data=json.load(sys.stdin); pattern=re.compile(sys.argv[1])
for asset in data.get("assets", []):
    if pattern.fullmatch(asset["name"]):
        print(asset["browser_download_url"]); break
else: raise SystemExit("未找到匹配资源："+sys.argv[1])' "$pattern"
}

MIHOMO_URL=${MIHOMO_URL:-$(asset_url MetaCubeX/mihomo 'mihomo-android-arm64-v8-v[^/]+\.gz')}

echo "下载 mihomo：$MIHOMO_URL"
curl -fL --retry 3 "$MIHOMO_URL" -o "$WORK_DIR/mihomo.gz"
gzip -dc "$WORK_DIR/mihomo.gz" > "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI/libmihomo.so"
chmod 0755 "$SOURCE_DIR/android/app/src/main/jniLibs/$ABI/libmihomo.so"

curl -fL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat \
  -o "$SOURCE_DIR/android/app/src/main/assets/geodata/geosite.dat"
curl -fL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat \
  -o "$SOURCE_DIR/android/app/src/main/assets/geodata/geoip.dat"
curl -fL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb \
  -o "$SOURCE_DIR/android/app/src/main/assets/geodata/country.mmdb"

cd "$SOURCE_DIR"
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64

APK="$SOURCE_DIR/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK" ] || { echo "Release APK 未生成" >&2; exit 1; }
unzip -t "$APK" >/dev/null
unzip -l "$APK" | grep 'assets/root/mclash_root.zip' >/dev/null || {
  echo "APK 不含 Root 模块 ZIP" >&2
  exit 1
}

APKSIGNER=${APKSIGNER:-$(find "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -n 1)}
[ -x "$APKSIGNER" ] || { echo "找不到 apksigner" >&2; exit 1; }
"$APKSIGNER" verify --verbose --print-certs "$APK" >/dev/null

cp "$APK" "$OUTPUT_DIR/Mclash-root-arm64-v8a.apk"
(cd "$OUTPUT_DIR" && sha256sum Mclash-root-arm64-v8a.apk > Mclash-root-arm64-v8a.apk.sha256)
echo "构建完成：$OUTPUT_DIR/Mclash-root-arm64-v8a.apk"
