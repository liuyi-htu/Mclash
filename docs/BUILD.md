# 构建与开发

[返回项目首页](../README.md)

以下构建命令在仓库根目录或指定客户端目录执行。

## Android 编译环境

| 组件 | 版本或要求 |
| --- | --- |
| Flutter | CI 与本地均使用 3.44.9 |
| Dart | Flutter 自带 3.12.2；项目要求 `>=3.6.0 <4.0.0` |
| Java | Temurin 17.0.20+8 |
| Android SDK Platform | Android 36，与 Flutter 的 `compileSdkVersion` 一致 |
| Android SDK Build Tools | 34.0.0，与当前 Gradle 实际选用版本一致 |
| Android NDK | 27.2.12479018 |
| Gradle | 8.10.2 |
| Android Gradle Plugin | 8.7.3 |
| Kotlin Gradle Plugin | 2.1.0 |
| 目标 CPU | ARM64（`arm64-v8a`） |
| 最低 Android 版本 | Android 7.0（API 24） |

Android SDK 需安装 Command-line Tools 和 Platform Tools。通过
`ANDROID_HOME`、`ANDROID_SDK_ROOT` 和客户端的 `android/local.properties`
配置 SDK；资源准备步骤还需 `sdkmanager`。当前工作区可在仓库根目录运行
`source ../.toolchains/env.sh` 加载本地工具链和缓存路径；此文件位于仓库外。系统还需要：

```text
git curl unzip gzip sha256sum file python3 java flutter dart
```

设备绑定流量监控构建另需 `openssl`。首次编译需联网下载 Android 组件、
Gradle、Dart 依赖和运行资源。

## 开发检查

进入 Android 客户端目录：

```bash
cd android
flutter pub get
flutter analyze
flutter test
```

## Android 构建

准备好 Release 签名配置和下方运行资源后执行：

```bash
cd android
./build-mclash-android.sh
```

默认构建 ARM64 Release APK，最终 APK 和 SHA-256 写入
`android/dist/`，本地文件名为 `Mclash-android-arm64-v8a-release.apk`；
GitHub 工作流会将其重命名为包含版本和构建号的文件。Android APK 和 Windows 安装包共用仓库中的
[`assets/default-config.yaml`](../assets/default-config.yaml)，仅作为用户主动添加订阅时的配置模板。
Android 和 Windows 首次安装均为空配置、空订阅，项目不内置任何公开机场订阅
或预设机场订阅链接。用户可自行导入 YAML 配置或添加自己的订阅。

Windows 构建脚本会将共享模板复制到 Flutter 的 [`assets/default-config.yaml`](../assets/default-config.yaml)；
单独运行 Flutter 命令前也需要先复制此文件。
如需 Debug APK：

```bash
BUILD_MODE=debug ./build-mclash-android.sh
```

VPN 的 TCP/UDP 53 流量交给 Mihomo 内部 DNS，IPv4/IPv6 跟随 VPN 开关；
VPN 参数不再提供 IPv4 DNS 输入框，程序保留 Android 所需的 DNS 接收地址。
内部 DNS 出口从普通代理组和 GLOBAL 中排除。DoH、DoT 等非 53 端口流量按普通代理规则处理。
HEV 的 2.17.1 源码及依赖保存在 `android/native/hev-socks5-tunnel`，DNS 接管和 UDP 会话修复直接维护在源码中。
GitHub 手动构建直接编译此目录，无需下载 HEV 或应用补丁；本地准备 JNI 运行库时也应编译此目录。

以下运行资源路径以 `android/` 客户端目录为起点：

```text
android/app/src/main/jniLibs/arm64-v8a/libmihomo.so
android/app/src/main/jniLibs/arm64-v8a/libhev-socks5-tunnel.so
android/app/src/main/assets/geodata/geosite.dat
android/app/src/main/assets/geodata/geoip.dat
android/app/src/main/assets/geodata/country.mmdb
```

缺少运行资源时 APK 可能仍能完成普通 Flutter 编译，但对应的代理模式无法
正常启动。

## Android Root 构建

### 本地构建

需要 Flutter、Java 17、Android SDK/NDK、Python 3、unzip 和 sha256sum。

```bash
cd root
./build-root-android.sh
```

默认下载官方 arm64 Mihomo 及 geodata，校验 GitHub Release 资产的 SHA-256，构建已签名的 release APK，执行 Flutter 分析、Flutter 测试及 Kotlin 单元测试。可通过 `MIHOMO_VERSION=v…` 固定内核版本；已准备资源时使用 `PREPARE_RUNTIME=0`。生成的资源、SDK 配置和 APK 不纳入 Git。

产物位于 `root/dist/`，名称包含版本和构建号，旁边有 `.sha256`。默认复用仓库上级目录 `signing/key.properties` 和其中指定的 keystore；也可通过 `root/android/key.properties` 或 `MCLASH_SIGNING_PROPERTIES` 指定。签名材料不复制、不修改、不纳入 Git。签名配置缺失时正式版构建会失败；`BUILD_MODE=debug` 可构建调试版本。

`.github/workflows/build-all.yml` 同时支持 Android VPN、Root 和 Windows 客户端。
Root 客户端版本参与发布后的自动同步。

### 验证边界

规则生命周期测试在模拟命令环境中覆盖正常停止、重复清理、中途失败及外部路由冲突，不会触碰开发机防火墙。还必须使用有 Root 的 Android 真机验证 TCP/UDP、DNS、分应用、热点接管及接口变化、网络切换、息屏、内核退出、强杀应用和卸载后的规则清理。未完成真机验证前，请将此版本视为开发版本。

参考：[Mihomo 透明代理端口](https://wiki.metacubex.one/config/inbound/port/)、[Linux TProxy 文档](https://cdn.kernel.org/doc/html/latest/networking/tproxy.html)。

## Windows 构建

Windows 10 或更高版本需安装 Flutter 3.44.9（启用 Windows 桌面支持）、Go 1.24.0、
Visual Studio C++ 构建工具和 Inno Setup 6。请在 PowerShell 中从仓库根目录执行：

```powershell
.\windows\scripts\build-windows.ps1
```

脚本会下载并校验 mihomo、GeoSite、GeoIP 和 Country 数据，运行
Dart 与 Go 检查，并将安装程序写入 `windows\installer\Output\`。Windows
客户端支持 mihomo/Clash YAML 配置，支持
TUN 与系统代理模式。

## GitHub 手动构建

GitHub Actions 不会因提交或修改文件自动构建。需要构建时，在仓库的
**Actions → Build Mclash clients → Run workflow** 中手动启动。参数如下：

- `target`：`all` 构建 Android VPN、Root 和 Windows；`android` 构建两个
  安卓版，`windows` 只构建 Windows。
- `version`：版本号，格式为 `x.y.z`；输入框预填最近成功发布的版本号。
- `build_number`：输入框预填最近成功发布的构建号。保持两个默认值不变运行时，
  工作流会自动使用下一个构建号；切换为尚未发布的新版本时，
  默认构建号从 `1` 开始。

工作流结合 `android/pubspec.yaml` 和所选版本已发布 Release 的最高构建号
确定递增基准。成功发布 Release 后会同步三个客户端的版本和工作流默认值。
选择单个平台构建
不会同步这些值，因此重复单端构建可能使用相同的构建号。同一分支的构建
共用一个并发队列。

Android 的 Release APK 使用以下仓库 Secrets 签名：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

`ANDROID_KEYSTORE_BASE64` 是 JKS/keystore 文件的 Base64 内容。构建完成后，
APK、Windows 安装程序及 SHA-256 文件会保存在对应的 Actions Artifacts 中。
选择 `target=all` 且三个客户端全部构建成功时，工作流还会创建
`v版本-b构建号` 标签和 GitHub Release，并把全部产物发布到同一个 Release；
选择单个平台构建时只保留 Artifact，不发布不完整的 Release。Release 发布
成功后，工作流会用 `[skip ci]` 提交直接更新 `main` 中的版本和构建号默认值，
不会创建额外分支，也不会触发新的构建。

## 签名与产物

Debug APK 使用 Android 调试证书。分发 Release APK 前必须完成正式签名。
Android VPN 客户端的签名配置为 `android/android/key.properties`，其
`storeFile` 可使用绝对路径，相对路径以该文件所在目录解析，必须指向存在的 JKS 或 keystore。
缺少或不完整的签名配置会使 VPN 客户端生成未签名的 Release APK；Root
客户端则会拒绝 Release 构建。Root 签名路径见上方本地构建说明。密钥和密码
不应上传或提交到公开仓库。

`android/build-mclash-android.sh` 在成功或失败退出时，都会删除客户端目录下
的 `build/`、`.dart_tool/`、`.pub/`、`android/.gradle/` 和 `android/.kotlin/`，
最终产物默认保留在 `android/dist/`。预先准备的 mihomo、HevSocks5Tunnel
和 geodata 文件也会在退出时删除。Root 构建脚本保留构建缓存和运行资源。

## 版本信息

三个客户端的版本分别在 `android/pubspec.yaml`、`root/pubspec.yaml` 和
`windows/mclash/pubspec.yaml` 中维护。Android VPN 客户端的包名为
`com.liuyihtu.mclash`，最低支持 Android 7.0（API 24）；Root 客户端的包名为
`com.liuyihtu.mclash.root`，支持独立本地构建及 GitHub 手动构建。
