# Android 普通 VPN 稳定性与轻量低功耗审查

日期：2026-10-19（Asia/Shanghai）。仅普通 Android VPN；不修改 Root、Windows、官方 Mihomo 内核或 Hev 转发算法。

已完成后续蜂窝网络真机验证，详见 [设备报告](ANDROID_VPN_DEVICE_TESTS.md)。下文代码审查与本地回归已同步更新；设备限制以该报告为准。

## 基准与范围

- GitHub main 基准：`c417662b0c39cb0d2724e3c6873cc4e98a0422fb`；本轮 `git ls-remote origin refs/heads/main` 确认不变。
- 工作开始即记录已有未提交状态及完整受跟踪差异；原记录在工作区 `.build-cache/android-vpn-audit-20261019/status-before.txt`、`tracked-before.patch`。
- 工作区已有三端 UI、普通版隐藏多任务卡片、Root 独立生命周期等修改。本轮在其上增量修改，不把这些既有差异算作本轮修复。
- `AGENTS.md`、`LOCAL_CHANGES.md` 留在本地；本轮不暂存、提交、推送、创建 PR 或启动 GitHub Actions。
- 原 `../env.sh` 不存在；实际工具链环境在 `../.toolchains/env.sh`。为限制写入范围，Flutter SDK、Android SDK 和构建副本均放在本项目 `.build-cache/android-vpn-audit-20261019/` 内。原工具链、签名和其他项目文件不改写。

## 数据路径与已有合理设计

Flutter `NativeProxyService` → `mclash/native` MethodChannel → `MainActivity` → `ProxyVpnService` 串行工作线程 → 官方 Mihomo 子进程 → Hev JNI 原生线程 → Android TUN。

- Mihomo 使用 APK 解压的 `libmihomo.so` 可执行文件；Hev 使用固定版本的随仓库源码、NDK 编译的 `libhev-socks5-tunnel.so`，通过 `JNI_OnLoad` 注册 Kotlin 入口。前台 VPN Service 必须保留。
- Mihomo 已依次确认本地混合端口 7890、DNS SOCKS 端口 7891、控制器 9090 可连接，不重复改写这套就绪检查。端口就绪不等于外部节点或互联网一定连通。
- Hev 将端口 53 交给独立 SOCKS DNS 入口，再由 Mihomo 内部 resolver 处理；其他 TCP/UDP 走普通 SOCKS 链路。保持用户上游 DNS、现有运行配置注入和 DNS 模式。
- 保持 `198.18.0.1/30`、可选 IPv6 `fc00::1/128`、默认路由/资源表中的局域网绕过路由、UDP、MTU、TCP Buffer、Hev Task Stack 及用户规则不变。
- Mihomo 与 App 同 UID；排除模式必须排除自身，允许模式不得加入自身，避免出站回环。
- Mihomo 非调试输出的阻塞读取线程及有界错误缓存是必要设计；保留。新增退出等待线程阻塞在 `waitFor()`，不执行周期探测。
- Mihomo 启动端口检查中的 200ms sleep、MethodChannel 操作等待中的 100ms sleep 都有操作时限，不是运行期间的常驻轮询。磁贴的单次延迟更新也不变。
- 订阅、规则更新与节点测速由用户操作触发，没有发现需移除的周期性后台下载。代理面板没有独立的流量 Timer；已有请求代次检查、销毁时关闭 HttpClient 和测速队列继续保留。

## 审查结论

| 问题 | 位置 | 级别 | 判断 | 处理 |
|---|---|---|---|---|
| 允许名单仅检查保存值，全部卸载时 Builder 实际名单为空 | `ProxyVpnService.applyPerAppFilter` | P0 | 已确认 | 已修复，先明确检查安装状态，至少一个非自身的有效应用成功添加，否则禁止 establish |
| JNI 创建线程就报告成功，初始化失败仍可被报告运行 | `hev-jni.c`、`hev-socks5-tunnel.c` | P0 | 已确认 | 已修复，初始化资源及注册转发任务后才发就绪信号 |
| Mihomo/Hev 运行后退出不主动撤销运行状态和清理资源 | `MihomoBridge.kt`、JNI、VPN Service | P0 | 已确认 | 已修复，使用进程退出等待/JNI 回调，无状态定时器 |
| 启动失败提前放开状态，清理异常被吞，旧销毁回调可能干扰下一次启动 | VPN Service | P0 | 已确认 | 已修复，单一阶段状态、串行清理及销毁完成后放行 |
| 授权撤销没有明确清理入口 | VPN Service | P0 | 已确认 | 已修复，立即取消启动并将收尾交主线程调度 |
| native 停止返回值、强杀后存活状态和 Java 管道关闭未完整处理 | VPN Service、Mihomo | P0/P1 | 已确认 | 已修复，确认回收再释放所有权；清理失败保留错误/句柄 |
| JNI 加载失败时回滚再次访问失败类，可跳过 Mihomo 清理 | VPN Service | P0 | 已确认 | 已修复，仅清除确已安装的监听器，其他清理各自尝试 |
| 日志写失败可能打断启动失败回滚/停止 | `StartupLog` | P1 | 已确认 | 已修复，日志写入失败退回 logcat，不打断生命周期 |
| 普通模式仍每两秒 stat 两个日志文件 | VPN Service | P1 | 已确认 | 已修复，普通会话完全不调度；调试限额维护保留 |
| 首页在其他标签/完整子页下采样流量，编辑器后台查状态 | Flutter 页面 | P1 | 已确认 | 已修复，生命周期和路由可见性控制，流量限可见运行首页 |
| 操作异常后首页直接显示停止 | `HomePage._toggle` | P0/P1 | 已确认 | 已修复，读取真实原生状态，读取失败保留过渡状态 |
| 首页原本已在 App 后台取消 Timer | Flutter 首页 | — | 正常设计 | 保留，增加路由可见性和销毁保护 |
| DNS、IPv4/IPv6、LAN、UDP、网络切换、私人 DNS | VPN/Hev/Mihomo 链路 | — | 正常设计／设备兼容性风险 | 蜂窝 DNS/TCP/UDP/IPv6 实测通过；Wi-Fi 切换、严格私人 DNS、LAN 端点及长稳未覆盖 |
| ROM Builder 静默接受未安装包名 | `PerAppFilter`、Service | P0 | 真机确认 | 增加 PackageManager 安装检查，避免实际空允许名单 |
| 冻结子进程在 Java 强杀后仍存活 | `ProcessCleanup`、`AndroidProcessTermination`、Mihomo | P0/P1 | 真机确认 | 仅超时降级，唯一确认自有 PID/UID/argv/start tick 后 SIGKILL；真实冻结停止通过 |

没有留下已确认、可安全复现且能在本次范围内验证而未处理的功能缺陷。以下不是已验证修复：

- 原生初始化或原生停止如果卡死，等待就绪/`pthread_join` 仍可能阻塞 Service 工作线程。主线程不执行这些操作；没有加入强行终止 JVM 内原生线程、无限重启或无限清理重试。宿主受控测试不能证明所有设备上原生转发永不挂起。
- 清理失败保留“正在停止”和句柄，阻止配置改写及重新启动，不能谎报停止成功；可再次明确调用现有 `stop` 通道重试。当前首页/磁贴在停止阶段仍禁用启动按钮，没有新增失败恢复 UI。若原生 join 永不返回，不能靠再次排队解决，需要设备故障诊断。
- 初始端口检查采用现有本地连接语义，不证明上游连通性、套接字归属或特定应用转发已经完成；这些要做端到端测试。
- 蜂窝网络转发及系统 VPN 撤销/重新授权已真机通过。小米上实际划卡结束整个应用，重开正确显示停止；严格私人 DNS、Wi-Fi 切换、长期耗电仍未覆盖。

## 文件、函数与前后行为

路径以仓库根目录为起点；本表只列本轮增量。

| 文件 | 函数/内容 | 修改前 → 修改后 |
|---|---|---|
| `android/android/app/src/main/kotlin/com/liuyihtu/mclash/PerAppFilter.kt`（新增） | `apply` | 持久名单非空不代表 Builder 非空 → 先检查安装状态，再统计实际允许添加成功数，过滤自身，排除自身失败也拒绝创建 |
| 同目录 `ProxyVpnService.kt` | `startProxy`、`applyPerAppFilter`、`requestStop`、`stopNativeComponents`、`onRevoke`、`onDestroy`、`componentExited` | 线程创建即运行、分散 Boolean、吞清理异常 → 原生就绪、阶段状态、退出事件、幂等排队、可诊断清理；旧 Service 销毁前不接纳新启动；全局单串行线程持有 TUN/Hev 句柄，旧清理完成不能放开新的停止请求 |
| 同目录 `VpnLifecycle.kt`（新增） | `requestStart/beginStart/finishStart/requestStop/finishStop` | 多 Boolean 可矛盾 → STOPPED/REQUESTED/STARTING/RUNNING/STOPPING；停止请求和完成结果带修订号，发送失败或旧清理完成不撤销较新的停止/授权撤销 |
| 同目录 `MihomoBridge.kt` | `start`、`stop`、`validateConfig` | 没有持续退出事件、提前丢进程引用 → `waitFor` 退出反馈、创建后即持有引用、确认退出并关闭管道；保留原始启动异常及清理异常 |
| 同目录 `ProcessCleanup.kt`（新增） | `terminate` | 强杀等待结果未检查、管道依赖后续回收 → 有界 TERM/KILL 等待、检查真正退出、逐个关闭三个 Java 管道；校验临时进程也使用同一清理 |
| 同目录 `AndroidProcessTermination.kt`（新增） | `readIdentity/findOwnedChild/killOwnedChild` | Java 强杀超时后无法可靠回收 → 唯一匹配并复核自有子进程身份后用公开 Os.kill；无 Root 或常驻扫描 |
| 同目录 `StartupLog.kt` | `reset`、`append` | 文件 I/O 异常可中断收尾 → 最佳努力写日志，失败记 logcat |
| 同目录 `MainActivity.kt` | `stopProxy`、`restartProxy` | 一律报告通用停止超时 → 优先显示 Service 保留的具体清理错误；该文件其他本地修改保留 |
| `android/android/app/src/main/kotlin/hev/htproxy/TProxyService.kt` | `onExit`、`tunnelExited(Int)` | 无原生退出反馈 → 带退出码的回调，保留 JNI 原有启动/停止/统计 API |
| `android/native/hev-socks5-tunnel/src/hev-jni.c` | `native_start_service`、`thread_handler`、`native_stop_service`、`hev_jni_tunnel_ready` | pthread 创建成功即返回 → 条件变量等待初始化成功或初始化失败；退出唤醒并回调 Java，失败启动回收线程 |
| 同目录 `hev-jni.h`、`hev-socks5-tunnel.c` | 声明、`hev_socks5_tunnel_run` 就绪通知 | 初始化边界无反馈 → 只增加 Android 库就绪通知，不改变转发任务/网络算法 |
| `android/lib/main.dart`、`shared/page_visibility.dart`（新增） | 路由 observer 注册 | 无完整子页可见性通知 → 复用 Flutter RouteObserver，未加入新依赖 |
| `android/lib/pages/home_page.dart` | 生命周期、路由回调、`_pollStatus/_updateTrafficSpeed`、状态 setter、`_toggle` | 其他标签仍流量采样、失败强置停止 → 后台/完整子页停 Timer，其他标签仅保留状态，运行首页一秒流量；停止直接清零，不再请求无用统计 |
| `android/lib/pages/config_editor_page.dart` | 生命周期、路由回调、`_startStateUpdates/_checkRunningState` | 后台继续一秒状态查询 → 后台/被完整子页覆盖时暂停，恢复仅一个 Timer，运行配置只读页不建 Timer；保留草稿逻辑 |
| `android/android/app/src/test/kotlin/com/liuyihtu/mclash/{PerAppFilterTest,VpnLifecycleTest,ProcessCleanupTest,AndroidProcessTerminationTest}.kt`（新增） | 36 项用例 | 覆盖卸载/重装/空名单/自身、阶段互斥/并发取消/重复启停/失败重试、进程清理/超时/管道异常 |
| `android/test/live_controls_test.dart`、`editor_lifecycle_test.dart`（新增） | 3 项新回归、既有回归 | 验证标签、完整页面、前后台、恢复无重复 Timer；保留原测试 |
| `android/native/tests/`（新增） | C 生命周期、受控转发桩、Java JNI 集成、运行脚本 | 30 轮线程生命周期 + 20 轮真实 JNI/JVM 集成；不是实际转发网络测试 |

## 性能与兼容性

- 普通模式删除整段每两秒检查两份原生日志的调度。普通 Hev 写 `/dev/null`，Mihomo 仍通过必要输出读取器保留有界错误缓存，不会让输出管道阻塞。
- 调试模式维持原来的 512KiB 触发、保留约 256KiB、同 inode 截断方案与两秒维护。突发输出可短暂超过阈值；不是每个写入字节都严格限制到 512KiB。停止时取消任务，销毁时关闭 executor。
- 取消 App 后台/完整页面覆盖下的管理层 Timer；可见首页流量仍是一秒。其他可见标签保留现有状态查询，以同步外部启停；不再读取流量。没有增加管理层高频轮询。
- VPN 控制工作线程和 native 句柄按进程内单例持有，跨 Service 实例保持串行，销毁失败后新实例仍能明确重试；空闲线程阻塞在队列，没有周期唤醒，不是独立守护进程。新增一个阻塞的 Mihomo 退出等待线程；Hev 在已有原生线程上一次性通知退出。必要的 Service、核心进程、输出读取器、原生调度线程不删除。
- 未测量待机电流、电池消耗或 CPU 降幅，不报告耗电改善百分比。进一步降低调试日志维护频率或状态刷新频率仅为可选项，本轮没有证据支持改变。

## 实际验证

所有构建/测试使用当前本地源码的隔离副本，未同步 GitHub 源码。实际缓存根目录：

`/home/zyh/Documents/program/mclash/.build-cache/android-vpn-audit-20261019`

环境入口为该目录中的 `environment.sh`；项目副本为 `project/android`。已运行：

```bash
# 在源码根目录：使用副本工具链，缓存/临时文件均位于本项目缓存
source ../.build-cache/android-vpn-audit-20261019/environment.sh
MCLASH_NATIVE_TEST_CACHE_DIR="$TMPDIR" android/native/tests/run-host-tests.sh

# 在缓存的 project/android：
flutter pub get
flutter analyze --no-fatal-infos
flutter test --no-pub
flutter build apk --debug --target-platform android-arm64 --no-pub
flutter build apk --release --target-platform android-arm64 --no-pub

# 在缓存的 project/android/android：最终源码重新编译与打包
./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain

# 在缓存的 hev-build：使用源码副本及其 .rev-id
"$ANDROID_NDK_HOME/ndk-build" APP_ABI=arm64-v8a \
  REV_ID="$(cat jni/.rev-id)" APP_MODULES=hev-socks5-tunnel -j8

# 源码中本轮变更的 Dart 文件格式检查，以及整个工作区差异检查
# Dart format 的实际文件列表在 format-final.log 中
git diff --check
```

结果：

- Flutter 全量 **200 项通过**。最终日志 `device-8b770685/flutter-test-final.log`；静态分析 `device-8b770685/analyze-final.log`，**No issues found**。
- Kotlin 全量 **83 项通过，0 失败/错误/跳过**，含新增 36 项；XML 在 `project/android/build/app/test-results/testDebugUnitTest/`。最终编译日志 `device-8b770685/android-force-stop-fix-build.log`。
- C 宿主测试 30 轮通过；真实 JNI/JVM 测试 20 轮、60 次带退出码回调通过，日志 `native-host-tests-final.log`。转发桩只验证就绪/线程回收/回调，不代表 TCP/UDP/TUN 真机通过。
- ARM64 Hev NDK 编译通过，日志 `ndk-build-final.log`。ARM64 Debug 和 Release APK 编译通过；最终同原签名 Release 为 `device-8b770685/Mclash-2.3.2-13-vpn-verified-arm64-release.apk`，已安装并实测蜂窝七项联网。打包完整性、签名有效性及最终 JNI 摘要比对结果在 `verification.json`。
- 本次新测试最初有 void await、模拟生命周期跳过中间状态的错误，已修复。完整回归还发现本轮停止采样导致停止后旧流量未清零，已修复并由原有测试验证；中间失败日志保留，不冒充通过结果。
- 构建有既有 Gradle/AGP/Kotlin 支持周期提示、SDK XML 版本提示和旧测试 unchecked cast 警告；未升级工具链或依赖。已完成本地 Release 构建、签名、安装及蜂窝网络测试；没有 GitHub 发布构建或电池耗电测量。

## 验收边界

下表保留初轮自动化的覆盖划分；后续已在 Android 16 蜂窝网络完成其中的启停/TUN、分应用卸载重装、异常回滚、授权撤销、页面追踪和日志上限，逐项结果与仍未覆盖项见 [设备报告](ANDROID_VPN_DEVICE_TESTS.md)。

| 验收项 | 本轮证据 | 仍需设备验证 |
|---|---|---|
| 正常启动、停止、重复请求、快速重启、启动中取消 | 状态对象用例、C/JNI 循环、Kotlin/ARM64 构建 | Android Service、TUN 与真实网络端到端 |
| 空/全部失效/部分失效/自身/重装/排除名单 | 12 项分应用逻辑测试；明确安装检查加 Builder 成功返回计数 | Android Builder 的 UID 生效、真实应用卸载/重装 |
| Mihomo 退出及清理 | 退出事件代码审查、进程回收测试（TERM/KILL/超时/管道失败） | 实际 Android 子进程异常退出及系统调度 |
| Hev 启动失败、意外退出 | C 失败注入、真实 JNI 注册与退出码回调 | Android ART、实际 TUN、网络任务异常 |
| 后台、隐藏页面 Timer | Flutter 生命周期/路由自动化；恢复无重复 Timer | 系统冻结、划卡和厂商行为 |
| 日志大小控制 | 原有 Unicode/同 inode/继续 append 测试通过；普通分支不调度 | 实际高输出速率与磁盘异常 |
| TCP、UDP、DNS、IPv6、LAN、私人 DNS、网络切换 | 配置/路由/算法未改变，原有 DNS 单测通过 | 真实分应用端到端网络 |

## 可直接使用的设备观察命令

以下为可重复使用的观察命令，不能单凭清单认定测试通过；已执行结果见设备报告。后续设备测试使用同原签名 Release，保留其他包及数据。多设备时在每个 adb 调用增加 `-s <设备序列号>`。

```bash
source ../.toolchains/env.sh
adb devices -l
adb shell am start -n com.liuyihtu.mclash/.MainActivity
adb shell dumpsys activity services com.liuyihtu.mclash
adb shell dumpsys connectivity
adb shell dumpsys vpn_management
adb shell ip addr
adb shell ip -4 route show table all
adb shell ip -6 route show table all
adb shell ss -lnt | rg ':(7890|7891|9090)\b'
adb shell ps -A -T | rg 'mclash|mihomo|hev|Hev'
adb logcat -v threadtime -T 1 | rg 'Mclash|AndroidRuntime|mihomo|hev|Hev|Vpn'
```

部分 Android 版本没有 `vpn_management` dumpsys 服务或不允许查看其他 UID 的 socket/路由；使用 `dumpsys connectivity`、应用启动日志和真实目标应用网络结果交叉确认，不能把权限失败当作 VPN 故障。

```bash
# 前后台、锁屏与系统状态观察
adb shell input keyevent KEYCODE_HOME
adb shell dumpsys deviceidle
adb shell dumpsys power
adb shell dumpsys batterystats com.liuyihtu.mclash
adb shell dumpsys alarm | rg 'mclash'

# 打开系统 VPN 设置后手动撤销/断开，并观察上述服务、进程与日志
adb shell am start -a android.settings.VPN_SETTINGS

# 仅对 debuggable 测试包：读取启用了调试日志的运行证据
adb shell run-as com.liuyihtu.mclash tail -n 100 files/runtime/startup.log
adb shell run-as com.liuyihtu.mclash wc -c files/mihomo/mihomo.log files/runtime/hev.log
```

Mihomo 异常退出注入（只在专用、可调试测试会话执行）：先用 `adb shell ps -A -o USER,PID,PPID,NAME,ARGS` 确认本包 `libmihomo.so` 子进程 PID，再设置 `MIHOMO_PID=实际数字` 并执行 `adb shell run-as com.liuyihtu.mclash kill -TERM "$MIHOMO_PID"`。期望 UI 离开运行态、TUN/子进程回收、无自动无限重启。正式包可能不支持 run-as；不要改为杀其他应用或系统进程。Hev 是 App 内原生线程，不用 kill 线程模拟失败；当前仓库宿主桩已覆盖启动失败及退出，设备端故障注入另行准备。

## 可重复执行的真机步骤与通过条件

1. 正常模式循环启停至少 10 次；启动中用已有磁贴停止，再启动。每次只有一套 Mihomo/Hev，停止后 Service、核心和 VPN 路由退出；不能只看按钮文字。启动失败后确认 TUN/进程释放，下一次启动正常。
2. 分应用依次测试：有效允许名单、有效/卸载混合、全部卸载、空名单、只含自身、自身加卸载应用、重装应用；全部无效必须明确拒绝创建 VPN。排除模式含空名单、有效及失效应用，始终排除 Mclash 自身。比较目标与非目标真实应用，不能用 adb shell UID 的联网结果替代选中应用。
3. 在被代理的网络测试应用中验证 TCP/HTTPS、UDP 回显、UDP/TCP DNS，以及 IPv6 开/关、局域网绕过开/关。使用自己的测试服务和原有配置；不改用户 DNS、节点、规则来制造“通过”。
4. 实际 Wi-Fi → 移动数据 → Wi-Fi 切换；测试私人 DNS 自动及用户原有严格模式、IPv6 网络、锁屏后恢复。允许必要连接重建；不能长期假运行或持续断网。
5. 系统设置撤销 VPN 授权，确认 native/TUN 清理；重新授权可启动。手动划掉最近任务卡片，分别验证隐藏卡片开关原功能及 VPN 是否按原有服务设计持续工作。不要把 force-stop 等同于划掉任务；普通 VPN 不采用 Root 独立守护。
6. 调试模式制造合理日志量，检查超过阈值后回落、可继续 append；普通模式长时间运行日志不被新写入，管理层没有两秒日志维护任务。记录前后台和打开子页时的采样变化。
7. 同设备、同网络/配置、同屏幕状态下断开充电进行待机对照，记录系统电池数据；长时间运行及厂商省电策略另测。本轮没有锁屏耗电、厂商后台或长稳结果。

必要修复是分应用失败关闭、原生初始化/退出反馈、串行生命周期与资源回收。已确认的无用日志检查和不可见流量采样已移除。继续降低刷新频率仅为可选项；VPN 服务、必要线程、网络定时器、双栈/DNS/UDP 策略与既有 UI 应保持现状。
