#!/usr/bin/env bash
# Linux host tests. Forwarding is stubbed; Android TUN networking requires a device.
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${JAVA_HOME:?Load the project toolchain environment first}"
output_root=${MCLASH_NATIVE_TEST_CACHE_DIR:-"$test_dir/../../build/native-tests"}
mkdir -p "$output_root"
run_dir=$(mktemp -d "$output_root/run.XXXXXX")
trap 'rm -rf -- "$run_dir"' EXIT
cc -DANDROID -DENABLE_LIBRARY -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" \
    -pthread "$test_dir/hev_jni_lifecycle_test.c" -o "$run_dir/lifecycle"
timeout 20s "$run_dir/lifecycle"
cc -DANDROID -DENABLE_LIBRARY -fPIC -shared -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" \
    -pthread "$test_dir/../hev-socks5-tunnel/src/hev-jni.c" \
    "$test_dir/hev_jni_test_core.c" -o "$run_dir/libhev-jni-test.so"
"$JAVA_HOME/bin/javac" -d "$run_dir/classes" "$test_dir/jvm/hev/htproxy/TProxyService.java"
timeout 20s "$JAVA_HOME/bin/java" -Djava.io.tmpdir="$run_dir" -cp "$run_dir/classes" \
    hev.htproxy.TProxyService "$run_dir/libhev-jni-test.so"
