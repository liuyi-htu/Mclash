# Mclash 源码说明

Mclash 是一款面向 Android 的 Flutter 图形客户端，通过本地 VPN 服务运行
mihomo，并提供配置管理、代理面板、代理规则、应用分流、快捷设置磁贴及运行状态
展示。界面使用 Material 3，Flutter 负责页面和交互，Android/Kotlin 负责 VPN、
配置存储、核心进程及系统能力。

## 源码结构

```text
source/
├── lib/
│   ├── main.dart                   # Flutter 应用入口和全局主题
│   ├── pages/                      # 首页、配置、代理面板等页面
│   ├── core/                       # 数据模型
│   ├── services/                   # Flutter 与 Android 的原生通道
│   └── shared/                     # 通用 UI 组件
├── android/
│   └── app/src/main/
│       ├── kotlin/                 # VPN、mihomo、配置和系统服务
│       └── res/                    # 图标、主题和 Android 资源
├── test/                           # Flutter 组件测试
├── pubspec.yaml                    # 项目版本与依赖
└── analysis_options.yaml           # Dart 静态检查规则
```

## 主要模块

- `pages/home_page.dart`：首页状态、代理启动入口、底部导航和设置区域。
- `pages/config_page.dart`：本地 YAML 与订阅配置管理。
- `pages/proxy_panel_page.dart`：代理组和节点选择。
- `services/native_proxy_service.dart`：统一封装 `mclash/native` 方法通道。
- `ProxyVpnService.kt`：Android VPN 生命周期和隧道管理。
- `MihomoBridge.kt`：mihomo 核心进程、端口与资源准备。
- `ConfigStore.kt`：配置文件及应用设置的持久化。

## 编译环境

推荐在 64 位 Ubuntu 或其他兼容的 Linux 环境中编译。项目当前使用的工具链如下：

| 组件 | 版本或要求 |
| --- | --- |
| Flutter | 3.32.8 |
| Dart | Flutter 自带版本；项目要求 `>=3.6.0 <4.0.0` |
| Java | OpenJDK 17，构建脚本会强制检查主版本 |
| Android SDK Platform | Android 35 |
| Android SDK Build Tools | 35.0.0 |
| Android NDK | 27.2.12479018 |
| Gradle | 8.10.2，由 Gradle Wrapper 自动下载 |
| Android Gradle Plugin | 8.7.3 |
| Kotlin Gradle Plugin | 2.1.0 |
| 目标 CPU | ARM64（`arm64-v8a`） |
| 最低 Android 版本 | Android 7.0（API 24） |

Android SDK 需要安装 Command-line Tools、Platform Tools，并确保 `sdkmanager`
可用。构建脚本默认从 `ANDROID_HOME`、`ANDROID_SDK_ROOT` 或
`$HOME/Android/Sdk` 查找 SDK。

系统还需要以下命令：

```text
git curl unzip gzip sha256sum file python3 java flutter dart
```

设备绑定构建额外需要 `openssl`。首次编译需要联网下载 Android 组件、Gradle、
Dart 依赖和运行资源。

## 开发检查

环境准备完成后，在 `source/` 目录执行：

```bash
flutter pub get
flutter analyze
flutter test
```

这些命令会生成 `.dart_tool/`、`build/` 等临时文件，它们已通过 `.gitignore`
排除，不属于源码。

## 构建 APK

普通源码直接使用 Flutter 编译。在 `source/` 目录先获取依赖：

```bash
flutter pub get
```

构建便于本地安装和调试的 Debug APK：

```bash
flutter build apk --debug --target-platform android-arm64
```

构建 ARM64 Release APK：

```bash
flutter build apk --release --target-platform android-arm64
```

构建结果位于：

```text
build/app/outputs/flutter-apk/app-debug.apk
build/app/outputs/flutter-apk/app-release.apk
```

完整运行代理功能还需要在编译前准备以下 ARM64 运行资源：

```text
android/app/src/main/jniLibs/arm64-v8a/libmihomo.so
android/app/src/main/jniLibs/arm64-v8a/libhev-socks5-tunnel.so
android/app/src/main/assets/geodata/geosite.dat
android/app/src/main/assets/geodata/geoip.dat
android/app/src/main/assets/geodata/country.mmdb
```

缺少这些文件时 APK 可能仍能完成编译，但代理核心和 VPN 隧道无法正常启动。
Debug APK 使用 Android 调试证书自动签名；Release APK 只有在
`android/key.properties` 配置完整且密钥文件存在时才会签名，否则会生成未签名包。
密钥和密码不应上传或提交到公开仓库。

## 版本信息

应用版本在 `pubspec.yaml` 中维护，当前 Android 包名为
`com.liuyihtu.mclash`，最低支持 Android 7.0（API 24）。
