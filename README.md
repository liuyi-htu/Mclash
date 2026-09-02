# Mclash源码说明

- `android/`：通过 Android `VpnService` 运行 mihomo 和 HevSocks5Tunnel，不依赖
  Root 权限。
- `windows/`：Flutter Windows 客户端，同时支持 mihomo 和 sing-box，通过
  独立的 Windows 系统服务管理代理内核、系统代理和更新。

## 目录结构

```text
Mclash/
├── README.md
├── android/
│   ├── lib/                        # Android 客户端 Flutter 源码
│   ├── android/                    # Android/Kotlin 源码
│   ├── test/                       # Flutter 组件测试
│   ├── build-mclash-android.sh     # Android 构建入口
│   └── dist/                       # Android 最终产物
└── windows/
    ├── mclash/                     # Flutter Windows 客户端
    ├── windows-service/            # Windows 系统服务
    ├── installer/                  # Inno Setup 安装配置
    └── scripts/build-windows.ps1   # Windows 构建入口
```

Android App 的 `lib/` 目录按职责划分：

- `main.dart`：Flutter 应用入口和全局主题。
- `pages/`：首页、配置、代理面板及应用选择页。
- `core/`：数据模型。
- `services/`：Flutter 与 Android 的 `mclash/native` 原生通道。
- `shared/`：通用 UI 组件。

## 模式特有模块

### Android

- `ProxyVpnService.kt`：Android VPN 生命周期和隧道管理。
- `MihomoBridge.kt`：mihomo 内核进程、端口和资源准备。
- `ConfigStore.kt`：配置文件及应用设置持久化。

### Windows

- `windows/mclash/`：桌面界面、配置管理和系统代理控制。
- `windows/windows-service/`：负责 mihomo、sing-box 生命周期、自启动和内核更新。
- `windows/installer/`：生成 Windows 安装程序。

## Android 编译环境

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
`android/dist/`。Android APK 和 Windows 安装包共用仓库中的
`assets/default-config.yaml`，构建时直接内置，不再访问远程配置地址。Android
应用仅在首次运行且没有现有配置时导入该配置。
如需 Debug APK：

```bash
BUILD_MODE=debug ./build-mclash-android.sh
```

Android 客户端需要：

```text
android/app/src/main/jniLibs/arm64-v8a/libmihomo.so
android/app/src/main/jniLibs/arm64-v8a/libhev-socks5-tunnel.so
android/app/src/main/assets/geodata/geosite.dat
android/app/src/main/assets/geodata/geoip.dat
android/app/src/main/assets/geodata/country.mmdb
```

缺少运行资源时 APK 可能仍能完成普通 Flutter 编译，但对应的代理模式无法
正常启动。

## Windows 构建

Windows 10 或更高版本需安装 Flutter（启用 Windows 桌面支持）、Go、
Visual Studio C++ 构建工具和 Inno Setup 6。请在 PowerShell 中从仓库根目录执行：

```powershell
.\windows\scripts\build-windows.ps1
```

脚本会下载并校验 mihomo、sing-box、GeoSite、GeoIP 和 Country 数据，运行
Dart 与 Go 检查，并将安装程序写入 `windows\installer\Output\`。Windows
客户端支持 mihomo/Clash YAML 配置和 sing-box JSON 配置，两种内核均支持
TUN 与系统代理模式。

## GitHub 自动构建

GitHub Actions 不会因提交或修改文件自动构建。需要构建时，在仓库的
**Actions → Build Mclash clients → Run workflow** 中手动启动。参数如下：

- `target`：构建全部客户端，或只构建 Android、Windows 之一。
- `version`：版本号，格式为 `x.y.z`；输入框预填最近成功发布的版本号。
- `build_number`：输入框预填最近成功发布的构建号。保持两个默认值不变运行时，
  工作流会自动使用下一个构建号；只修改为新版本时，构建号从 `1` 开始。

工作流通过最近发布的 `v版本-b构建号` Release 标签识别上一次构建版本。仓库
尚无新格式 Release 时，会以 `android/pubspec.yaml` 中的版本作为初始依据。所有
构建共用同一个并发队列，避免并行任务取得相同构建号。

Android 的 Release APK 使用以下仓库 Secrets 签名：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

`ANDROID_KEYSTORE_BASE64` 是 JKS/keystore 文件的 Base64 内容。构建完成后，
APK、Windows 安装程序及 SHA-256 文件会保存在对应的 Actions Artifacts 中。
选择 `target=all` 且两个客户端全部构建成功时，工作流还会创建
`v版本-b构建号` 标签和 GitHub Release，并把全部产物发布到同一个 Release；
单独构建某个客户端时只保留 Artifact，不发布不完整的 Release。Release 发布
成功后，工作流会用 `[skip ci]` 提交直接更新 `main` 中的版本和构建号默认值，
不会创建额外分支，也不会触发新的构建。

## 签名与产物

Debug APK 使用 Android 调试证书。Release APK 必须使用正式签名；
`android/key.properties` 需配置完整，其 `storeFile` 必须指向存在的 JKS 或
keystore。密钥和密码不应上传或提交到公开仓库。

Android 构建脚本在成功或失败退出时，都会删除 `build/`、`.dart_tool/`、
`.pub/`、`android/.gradle/` 和 `android/.kotlin/`，仅在 `dist/` 保留最终产物。
编译期间准备的解压后 mihomo、HevSocks5Tunnel 和 geodata 文件会在退出时删除。

## 版本信息

两个客户端的版本分别在 `android/pubspec.yaml` 和
`windows/mclash/pubspec.yaml` 中维护。Android App 的包名为
`com.liuyihtu.mclash`，最低支持 Android 7.0（API 24）。

## 开源许可

Mclash 自身源代码依据 [GNU General Public License v3.0](LICENSE) 开源，
完整条款以仓库中的 `LICENSE` 文件为准。

构建和运行过程中使用的 mihomo、sing-box、HevSocks5Tunnel、Flutter 及规则
数据库等第三方项目，仍分别受其上游许可证和版权声明约束。使用或分发构建
产物时，请同时遵守并保留相应第三方项目的许可证及声明：

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)
- [heiher/hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel)
- [Flutter](https://github.com/flutter/flutter)
- [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)
