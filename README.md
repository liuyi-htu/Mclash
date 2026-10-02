# Mclash 源码说明

- `android/`：通过 Android `VpnService` 运行 mihomo 和 HevSocks5Tunnel，不依赖
  Root 权限。
- `root/`：独立的 Android Root TProxy 客户端，使用 mihomo，支持本机应用与热点代理。
- `windows/`：Flutter Windows 客户端，使用 mihomo，通过
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
├── root/
│   ├── lib/                        # Root 客户端 Flutter 源码
│   ├── android/                    # Root TProxy/Kotlin 源码
│   ├── test/                       # Flutter 组件测试
│   ├── scripts/                    # 运行资源准备与规则测试
│   ├── build-root-android.sh       # Root 客户端独立构建入口
│   └── dist/                       # Root 客户端最终产物
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

### Android Root

- `ProxyTProxyService.kt`：Root 代理生命周期和热点接口监测。
- `TProxyRules.kt`、`HotspotRules.kt`：本机与热点的透明代理规则。
- `RootRuntimeConfig.kt`：生成 Root 模式运行配置。
- `MihomoBridge.kt`：Root shell 守护进程与 mihomo 内核管理。

### Windows

- `windows/mclash/`：桌面界面、配置管理和系统代理控制。
- `windows/windows-service/`：负责 mihomo 生命周期、自启动和内核更新。
- `windows/installer/`：生成 Windows 安装程序。

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
`source ../env.sh` 加载本地工具链和缓存路径；此文件位于仓库外。系统还需要：

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
`assets/default-config.yaml`，仅作为用户主动添加订阅时的配置模板。
Android 和 Windows 首次安装均为空配置、空订阅，项目不内置任何公开机场订阅
或预设机场订阅链接。用户可自行导入 YAML 配置或添加自己的订阅。

Android 和 Windows 添加、修改或更新机场订阅时，先下载 Mihomo/Clash YAML
订阅，提取其中的 `proxies` 节点并内置到默认配置生成的订阅配置中。默认 DNS、
规则和代理分组保持一致，分组由软件按正则筛选后写入明确的 `proxies` 节点列表，不使用 `filter`；
默认国内正则为 `上海`，国外正则为 `KR`，没有匹配节点时使用 `DIRECT`。
订阅需要直接包含节点，仅包含远程 `proxy-providers` 的订阅会提示错误。
下载或解析失败时保留原配置；已有订阅在下次更新后应用此行为。
长按机场订阅可修改“国内正则表达式”和“国外正则表达式”，对应配置中的
`🚀 国内`、`🌍 国外` 分组的节点列表。正则保存在配置注释中，更新时继续使用。
机场订阅不提供手动编辑 YAML 配置的入口；本地 YAML 配置仍可编辑，运行配置只读。
订阅菜单顶部显示名称、剩余流量和到期时间。添加或更新订阅时保存机场返回的流量信息，
未提供或无效的流量信息显示“未提供”，到期时间未提供时显示“不限时”；
已有订阅需手动更新一次以获取这些数据。
“添加节点”仅列出手动节点，新添加的节点置顶，更新订阅后手动节点仍排在机场节点之前，可直接删除；删除时同步清理分组和代理链引用。
更新订阅只替换机场节点，手动节点的字段保持原样；主动修改 Host、正则和代理链时仍包含手动节点。
修改 Host、正则或代理链前需要先停止代理。修改保存到对应配置；如果该配置
当前已启用，则同时更新运行配置。更新订阅会保留正则；正则留空时匹配全部节点。
运行配置始终属于当前启用的配置，添加订阅后需要点击它切换；停止代理时
“查看当前运行配置”显示当前配置的预览，运行期间显示内核正在使用的文件。
链式节点可选择多个节点，按列表顺序依次连接，再连接所选作用节点；
列表支持拖动排序并保留已选节点，支持新增和编辑多条独立链路。设置操作取消或保存后返回原订阅设置菜单。

Windows 构建脚本会将共享模板复制到 Flutter 的 `assets/default-config.yaml`；
单独运行 Flutter 命令前也需要先复制此文件。
如需 Debug APK：

```bash
BUILD_MODE=debug ./build-mclash-android.sh
```

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

## Android Root 客户端

独立的 Android Root TProxy 客户端。基于仓库 Android 客户端的 Flutter 界面和配置管理开发，包名为 `com.liuyihtu.mclash.root`，可以与 `com.liuyihtu.mclash` 同时安装。

### 接管方式

本机应用 → iptables OUTPUT 打标 → IPv4 策略路由回送到 lo → PREROUTING TPROXY → Mihomo。

- 支持本机 IPv4 TCP、UDP，保留订阅、节点选择、规则/全局/直连及分应用代理。
- 需要用户授予 `su` 权限；设备内核和 iptables 必须支持 TPROXY、MARK、owner、REDIRECT、REJECT 和策略路由。
- 不建立 VpnService，不加载 HEV。默认接管 Android 报告为共享网络状态的热点接口，并随接口变化更新规则；热点客户端的 IPv4 TCP/UDP 经 TProxy 接管，DNS 53 重定向到 Mihomo，IPv6 TCP/UDP 阻断。热点流量不按本机应用列表过滤。
- 本应用和 UID 0 的 Root 程序普通数据流量直连，避免透明代理响应和内核出站回环；UID 0 的 IPv4 DNS 53 仍被重定向，以处理系统解析器请求。共享 UID 的应用会共同生效，分应用选择针对当前 Android 用户已安装的应用。
- 首版使用 IPv4。纳入代理范围的应用，其公网 IPv6 TCP/UDP 通过 ip6tables 阻断；未纳入代理范围的应用保留直连。IPv6 DNS 53 对非 Root、非本应用流量统一阻断，促使解析器使用 IPv4。
- 本机 IPv4 TCP/UDP DNS 53 除本应用和带内核出站标记的流量外，统一重定向到 Mihomo（包括 UID 0）；系统 DNS 通常由 netd 发出，因此 DNS 不按应用列表过滤。不会改写 Android 的私人 DNS 设置；严格私人 DNS 开启时拒绝启动。应用内 DoH/DoT 作为普通 TCP/UDP 按代理范围处理，不保证获得域名规则信息。
- 运行时生成独立配置，保留订阅的上游 DNS、节点和规则，固定代理与控制器的本机监听、DNS 监听、`redir-host`、IPv4 和出站标记，并移除导入配置的 TUN、自定义入站和外部控制监听。原配置文件不变。

### 生命周期与恢复

Root shell 守护进程同时管理内核和防火墙。端口准备完成后才安装规则；安装失败、正常停止、内核退出或应用进程消失时撤销规则，再结束内核。用应用 PID 和进程起始时间识别进程退出，避免 PID 重用和休眠造成误判。清理失败时保留内核并重试，应用显示错误而不是宣称已停止。

只使用 `MCLASH_R_*` 专用链、路由表 `20230`、优先级 `9000` 和高位 mark 掩码。检测到路由表/优先级冲突时拒绝启动，不清空系统防火墙或替换其他应用路由。标记与 Android/其他 Root 网络软件的兼容性仍需逐机验证。

设置 → TProxy 参数 → 清理残留规则，可在停止状态下清理上次留下的专用规则。启动前也会等待旧守护进程退出并清理残留。应用启动诊断、Mihomo 和守护进程日志可在调试日志中查看。

端口：mixed `17890`、TProxy `17894` 和控制器 `9090` 监听 `127.0.0.1`；
DNS 监听 `0.0.0.0:11053`，用于本机与热点 DNS 重定向。控制器端口与
Android VPN 客户端相同；两个客户端同时接管网络的组合尚未验证。

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

## 开源许可

Mclash 自身源代码依据 [GNU General Public License v3.0](LICENSE) 开源，
完整条款以仓库中的 `LICENSE` 文件为准。

构建和运行过程中使用的 mihomo、HevSocks5Tunnel、Flutter 及规则
数据库等第三方项目，仍分别受其上游许可证和版权声明约束。使用或分发构建
产物时，请同时遵守并保留相应第三方项目的许可证及声明：

- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
- [heiher/hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel)
- [Flutter](https://github.com/flutter/flutter)
- [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)

## 本地 Mihomo 网页面板

Android、Root 和 Windows 随应用内置 zashboard 网页资源。启动 Mihomo 后，
在同一设备的浏览器访问 `http://127.0.0.1:9090/ui/`，面板默认连接本机内核。
无需在线下载网页，也不增加应用界面入口；停止内核后面板服务随之停止。
控制器只监听本机回环地址，其他设备不能通过局域网访问。

内置资源固定到 Zephyruso/zashboard 的 `v3.29.1` 完整离线预构建版本，原始 MIT 许可证保存在面板资源目录的 `LICENSE` 文件中。
