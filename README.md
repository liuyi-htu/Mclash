# Mclash Root / VPN 源码说明

`source/` 同时维护 Mclash 的 Root 和 VPN 两种 Android App。两者共用 Flutter
界面和大部分配置能力，但使用不同的代理启动方式：

- `root/`：通过 Root 模块运行 mihomo，使用 `/data/adb/modules/mclash_root`
  模块和 `/data/adb/mclash` 数据目录，支持 Magisk、KernelSU 和 APatch。
- `vpn/`：通过 Android `VpnService` 运行 mihomo 和 HevSocks5Tunnel，不依赖
  Root 权限。

## 目录结构

```text
source/
├── README.md
├── root/
│   ├── lib/                        # Root 模式 Flutter 源码
│   ├── android/                    # Root 模式 Android/Kotlin 源码
│   ├── root-module/                # Magisk/KernelSU/APatch 模块
│   ├── test/                       # Flutter 组件测试
│   ├── build-mclash-root.sh        # Root 构建入口
│   └── dist/                       # Root 最终产物
└── vpn/
    ├── lib/                        # VPN 模式 Flutter 源码
    ├── android/                    # VPN 模式 Android/Kotlin 源码
    ├── test/                       # Flutter 组件测试
    ├── build-mclash-vpn.sh         # VPN 构建入口
    └── dist/                       # VPN 最终产物
```

每个 App 的 `lib/` 目录按职责划分：

- `main.dart`：Flutter 应用入口和全局主题。
- `pages/`：首页、配置、代理面板及应用选择页。
- `core/`：数据模型。
- `services/`：Flutter 与 Android 的 `mclash/native` 原生通道。
- `shared/`：通用 UI 组件。

## 模式特有模块

### Root

- `RootManager.kt`：Root 权限、模块、mihomo 内核和路由生命周期。
- `ConfigStore.kt`：配置文件及应用设置持久化。
- `root-module/`：可安装的 Root 模块源码。

### VPN

- `ProxyVpnService.kt`：Android VPN 生命周期和隧道管理。
- `MihomoBridge.kt`：mihomo 内核进程、端口和资源准备。
- `ConfigStore.kt`：配置文件及应用设置持久化。

## 编译环境

| 组件 | 版本或要求 |
| --- | --- |
| Flutter | 项目基线 3.32.8 |
| Dart | Flutter 自带；项目要求 `>=3.6.0 <4.0.0` |
| Java | OpenJDK 17 |
| Android SDK Platform | Android 35 |
| Android SDK Build Tools | 35.0.0 |
| Android NDK | 27.2.12479018 |
| Gradle | 8.10.2 |
| Android Gradle Plugin | 8.7.3 |
| Kotlin Gradle Plugin | 2.1.0 |
| 目标 CPU | ARM64（`arm64-v8a`） |
| 最低 Android 版本 | Android 7.0（API 24） |

Android SDK 需安装 Command-line Tools 和 Platform Tools，并确保 `sdkmanager`
可用。构建脚本从 `ANDROID_HOME`、`ANDROID_SDK_ROOT` 或
`$HOME/Android/Sdk` 查找 SDK。系统还需要：

```text
git curl unzip gzip sha256sum file python3 java flutter dart
```


## 开发检查

进入要检查的模式目录：

```bash
cd source/root # 或 cd source/vpn
flutter pub get
flutter analyze
flutter test
```

## Root 构建

准备好 Release 签名配置后执行：

```bash
cd source/root
./build-mclash-root.sh
```

脚本会下载最新 mihomo 和 geodata，执行格式化、静态分析、测试、Release
编译、APK 完整性和签名验证。最终 APK、在线更新内核压缩包和内核更新
manifest 写入 `source/root/dist/`。Root 模块不使用 Gradle 的上次打包结果，
每次构建都会从当前 `root-module/` 源码重新生成 ZIP 并嵌入 APK。
独立的 Root 模块 ZIP 只是构建中间文件，不会保留在 `dist/`。

Root 模式需要以下 ARM64 运行资源：

```text
android/app/src/main/jniLibs/arm64-v8a/libmihomo.so
android/app/src/main/assets/geodata/geosite.dat
android/app/src/main/assets/geodata/geoip.dat
android/app/src/main/assets/geodata/country.mmdb
```

## VPN 构建

准备好 Release 签名配置和下方运行资源后执行：

```bash
cd source/vpn
./build-mclash-vpn.sh
```

默认构建 ARM64 Release APK，最终 APK 和 SHA-256 写入
`source/vpn/dist/`。如需 Debug APK：

```bash
BUILD_MODE=debug ./build-mclash-vpn.sh
```

VPN 模式需要：

```text
android/app/src/main/jniLibs/arm64-v8a/libmihomo.so
android/app/src/main/jniLibs/arm64-v8a/libhev-socks5-tunnel.so
android/app/src/main/assets/geodata/geosite.dat
android/app/src/main/assets/geodata/geoip.dat
android/app/src/main/assets/geodata/country.mmdb
```

缺少运行资源时 APK 可能仍能完成普通 Flutter 编译，但对应的代理模式无法
正常启动。

## 签名与产物

Debug APK 使用 Android 调试证书。Release APK 必须使用正式签名；
`android/key.properties` 需配置完整，其 `storeFile` 必须指向存在的 JKS 或
keystore。密钥和密码不应上传或提交到公开仓库。

两个模式的构建脚本在成功或失败退出时，都会删除 `build/`、`.dart_tool/`、
`.pub/`、`android/.gradle/` 和 `android/.kotlin/`，仅在各自的 `dist/` 保留
最终产物。编译期间准备的解压后 mihomo、HevSocks5Tunnel 和 geodata 文件会在
退出时删除；Root `dist/` 会保留用于在线更新的 mihomo `.gz` 及 manifest。

## 版本信息

两个 App 的版本分别在 `source/root/pubspec.yaml` 和
`source/vpn/pubspec.yaml` 中维护。当前 Android 包名均为 `com.liuyihtu.mclash`，最低支持
Android 7.0（API 24）。
