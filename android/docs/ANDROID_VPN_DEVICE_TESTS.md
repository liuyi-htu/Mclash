# Android 普通 VPN 蜂窝网络真机验证

日期：2026-10-19（Asia/Shanghai）。基准 GitHub `main`：`c417662b0c39cb0d2724e3c6873cc4e98a0422fb`（当日再次查询确认）。本报告补充并更新 [代码审查报告](ANDROID_VPN_STABILITY_REVIEW.md) 的设备验证结果。

## 环境、范围与方法

- 小米 25113PN0EC，Android 16，ARM64；按用户要求关闭 Wi-Fi，使用手机蜂窝网络。测试时 USB 充电，不提供耗电百分比结论。
- 手机原先只安装 Root 版；普通版单独安装，保留 Root 包、数据和配置，未启动 Root 服务。生产普通 VPN 的实现和测试均不依赖 Root；ADB Root 仅用于安装、故障注入、读取诊断和系统调用追踪。
- 普通版使用本次创建的临时直连配置，不使用或修改用户订阅、节点、私人 DNS、Root 规则。分应用测试暂时使用测试配置 `MATCH,REJECT`，通过两个真实独立 UID 的测试应用验证选中/排除范围，结束后恢复直连配置。
- 临时 instrumentation 调用真实生产 Service/JNI，没有给源码增加测试后门。网络探针以实际前台 Activity 发包，不绑定或绕过 VPN 网络；检查实际 `NetworkCapabilities` 的 transport。不能把能力字符串中的 `NOT_VPN` 误判为 VPN transport。
- 最初后台 instrumentation 发 UDP 出现 `EPERM`，对照无 VPN 时也相同；netpolicy 指向 `APP_BACKGROUND`。改用前台探针后通过，没有更改防火墙或系统后台策略。中间失败日志保留，以下仅列修正后的结果。
- 私密原始证据及临时工具只在本项目缓存 `.build-cache/android-vpn-audit-20261019/device-8b770685/`，不纳入源码仓库。报告不包含用户设备账号、电话、订阅或签名秘密。

## 真机发现及修复

| 问题 | 实测依据 | 最小修复和结果 |
|---|---|---|
| 此 ROM 的 `VpnService.Builder.addAllowedApplication` 接受未安装包名 | PackageManager 返回未安装，而 Builder 调用正常返回；原仅凭添加成功的计数会错误通过 | `PerAppFilter` 增加明确安装检查；有效且非自身的包实际加入至少一个才允许启动。空/全部卸载/仅自身均拒绝；混合失效及重装通过 |
| 被 SIGSTOP 的 Mihomo 在 Java `destroyForcibly` 后仍存活 | 真实冻结子进程后停止超时，仍为 stopped 状态 | 新增 `AndroidProcessTermination`：只在 Java 强杀超时后，按父 PID、UID、完整 argv、start tick 唯一确认并复核自有进程，再以普通 App 权限发送 SIGKILL。没有周期扫描或 Root 依赖；实测约 5.23 秒完成停止，子进程与 TUN 清理，之后可重启 |

`MihomoBridge` 主进程和配置校验进程均接入有界清理降级；不能确认身份则保留失败及所有权，拒绝错误地报告停止。新增/补充安装检查、进程清理、身份识别单测；Kotlin 全量由初轮 74 项增加为 **83 项**。

## 实际执行结果

| 项目 | 结果及边界 | 主要本地证据 |
|---|---|---|
| 蜂窝直连与 VPN 对照 | 实际 CELLULAR / CELLULAR\|VPN；系统 DNS、UDP/TCP DNS、HTTP 204、HTTPS 200 均通过 | `probe/cellular-*-front-v2.log` |
| 普通 UDP、IPv6 | IPv4 与 IPv6 STUN 均收到匹配 transaction/cookie 的真实响应，VPN 和无 VPN 对照通过；不是仅成功发送数据包 | `probe/cellular-generic-udp-{ipv6,baseline}.log` |
| 最终 Release 真实流量 | DNS 三项、HTTP、HTTPS、IPv4/IPv6 UDP 七项均通过，实际 CELLULAR\|VPN | `probe/release-cellular-front.log` |
| 启停/重复请求 | 10 轮启动、重复启动、停止、重复停止；启动约 253–305ms，普通停止约 152–205ms。运行时一个 Mihomo/TUN，停止后均无残留 | `lifecycle-suite-force-fixed.log`、`lifecycle-results.json` |
| 启动取消 | 5 轮立即停止启动中的 Service，无假运行、无残留 | 同上 |
| 允许名单拒绝场景 | 空名单、全部未安装、仅自身、自身加未安装四类均拒绝并清理 | 同上 |
| 真实分应用 | 仅代理 A、A 加失效、自身加 A：A 被测试规则拒绝，B 蜂窝直连；排除 A 加失效：A 直连，B 被拒绝；排除空名单：两者进入 VPN | `per-app-suite-final.log`、`per-app-results.json` |
| 真实卸载/重装 | 卸载唯一选中测试应用后启动拒绝；重装后重新检查，选中 UID 进入 VPN，另一 UID 绕过 | 同上 |
| Mihomo 异常退出/冻结 | 对自有真实子进程 TERM 后退出事件触发清理；SIGSTOP 后停止走上述降级并清理，再启动成功 | `lifecycle-results.json` |
| 启动回滚 | 错误 Mihomo 配置失败并清理；实际 ART 下 Hev 非法配置启动失败后可重启；冷启动缺失 JNI 时，已创建的 Mihomo/TUN 均回滚；库原摘要恢复后冷启动成功 | `native-fault-suite.log`、`native-fault-results.json` |
| 系统撤销授权 | 在系统 VPN 设置实际“取消保存”，状态归零、Mihomo/TUN 清理、系统重新需要授权；通过实际授权弹窗恢复，七项联网通过 | `vpn-revoke-result.json`、`ui-vpn-forget-dialog.xml`、`ui-consent.xml`、`probe/cellular-after-system-consent.log` |
| 页面与后台采样 | strace 各观察 10 秒：首页 5 次 `/traffic`，设置页 0、后台 0，重新确认首页后恢复 5 次；这些窗口 `/connections` 均为 0 | `ui-{home-normal,settings-normal,background-normal,home-return-confirmed}-trace.json` |
| 普通/调试日志维护 | 上述普通模式窗口两份日志周期文件操作为 0；调试模式 8 秒内两份各 8 次文件操作。分别追加超过阈值的 UTF-8 测试日志后回到约 256KiB，同 inode 且 UTF-8 可解码，VPN 保持运行 | `debug-log-maintenance-trace.json`、`log-limit-results.json` |
| IPv6 关闭 / LAN 绕过开启 | 两种设置下，蜂窝 DNS 三项及 HTTP/HTTPS 均通过；没有把蜂窝公网验证记成真实局域网端点验证 | `mobile-settings-results.json` |
| 最近任务划卡 | Debug 和未挂目标 instrumentation 的 Release 均实测：卡片消失，厂商结束整个应用，Mihomo/TUN 随之消失；重开正确显示停止。此设备上划卡后不能继续保活，未改成 Root 守护或绕过系统管理 | `release-before-swipe-state.json`、`release-after-swipe-state.json`、`ui-release-reopen.xml` |
| 隐藏最近任务卡片 | Release 界面开关开启后，回桌面再进最近任务，无普通版卡片，原应用/core PID 与 TUN 保留；恢复开关为关闭。直接从当前前台打开最近任务可能仍显示当前任务，不能混同后台结果 | `ui-hide-background-recents.xml`、`release-hide-on-background-state.json`、`ui-hide-restored.xml` |
| Release 短时锁屏 | 12 次有效采样，连续约 168 秒应用/core PID 与 TUN 保持不变，确认系统锁屏且屏幕关闭；之后主动停止。计划第 13 次采样前已进入收尾，整段脚本不计完整通过；有效观察不能替代整夜、Doze 或耗电测试 | `release-lock-results.json`、`release-lock-observation.json` |

额外 Release 回归中，两轮重复启停的 RPC 已返回正常；冻结场景时 ADB USB/转发通道中断，未收到完整结果，故该额外场景不计通过。重新连接后确认核心/TUN 已消失，重建测试会话、恢复普通版默认 IPv6 关闭/LAN 绕过开启等参数，再启动约 308ms、停止约 202ms，通过。早先修复 Debug 包的完整冻结测试结果仍单独有效，不将其冒充该次 Release 故障测试结果。系统进程退出记录明确标注划卡为 `SwipeUpClean`，与崩溃区分。

STUN 使用 Cloudflare 公共服务，参考其[官方连接说明](https://developers.cloudflare.com/realtime/sfu/get-started/connection-patterns/)。没有关闭 TLS 证书校验。

## 本地回归与最终包

- Flutter **200 项全量通过**，静态分析 **No issues found**；`device-8b770685/flutter-test-final.log`、`analyze-final.log`。
- Kotlin **83 项、0 失败/错误/跳过**；`android-force-stop-fix-build.log` 及构建副本 `build/app/test-results/testDebugUnitTest/`。
- 既有本轮 C 生命周期 30 轮、JNI/JVM 20 轮及 60 次退出回调通过；ARM64 Hev NDK 编译通过。之后真机阶段没有修改原生源码，最终 APK 中 Hev 摘要与本次 NDK 输出一致。
- ARM64 Debug、ARM64 Release 本地构建通过；Release 使用原签名签署、验证后覆盖安装普通包。最终流量及划卡测试来自该 Release。
- 最终文件：缓存 `device-8b770685/Mclash-2.3.2-13-vpn-verified-arm64-release.apk`，SHA-256：`1f423a871cfab4973a6c1359fa190e74cdaa2b00911ea5dab73cc5723ff60c59`。
- 最终摘要核对：665 个 Dart/Kotlin/原生构建输入与当前源码一致；48 个本轮范围外受跟踪差异逐段保持不变；ZIP、签名、JNI 摘要及 `git diff --check` 通过。总结果位于缓存根目录 `verification.json`。
- 未提交、推送、创建 PR、发布 Release 或启动 GitHub Actions。Root/Windows 既有改动保留。

## 尚未覆盖的边界

- 按本轮用户要求仅用手机流量，未执行 Wi-Fi/蜂窝切换或 Wi-Fi 局域网端点测试。
- 保留设备原私人 DNS 状态（默认 off），没有替用户设置严格私人 DNS 主机；严格模式兼容性仍需单独测试。
- USB 充电状态下不能得出锁屏耗电改善；未执行整夜待机、长期稳定性、多 ROM/OEM 或全部网络覆盖测试。短时锁屏不代表已覆盖 Doze。
- 未强制破坏运行中的 JVM 原生线程来制造 Hev 内部运行故障；实际 ART 初始化失败、JNI 加载失败与宿主退出回调已覆盖，不能证明所有原生挂起均可恢复。原生 join 若永久卡住仍需诊断，未做不安全线程强杀。
- 当前小米划卡结束普通 VPN 是实测限制；普通 VpnService 的进程与核心无法在整个应用被厂商杀掉后独立维持。本轮没有改变后台管理、安全设置或引入无限重启。

## 最终收尾

Release 锁屏有效观察约 168 秒，边界如上表；未测电池。普通版保留最终同原签名 Release，处于停止状态，IPv6/LAN 绕过等参数恢复源码默认，隐藏卡片与调试日志关闭，分应用为排除空名单。保留明确命名的临时直连配置“普通VPN真机验证”，没有用户节点。

三份临时测试/探针包已卸载；设备临时 APK/XML/trace、测试注入日志和 ADB 19291 转发已移除。Root 包及配置保留；最终无 Mihomo/TUN 残留。Wi-Fi 关闭、蜂窝与私人 DNS 设置值与测试前记录一致。最后生产 stop 已由 RPC 确认成功，之后因转发再次失效，以 force-stop 结束已空闲的 instrumentation 会话；该操作不用于冒充生产停止通过，结束前后均独立检查无核心/TUN。清理结果在 `cleanup-result.json`。仅本项目缓存保留诊断，未发布原始私密设备数据。
