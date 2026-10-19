# Root 生命周期与低功耗审查

审查始于 2026-10-18，最终验证更新于 2026-10-19。依据当前本地源码；不更改用户订阅、规则、DNS、节点或协议。

清理更新（2026-10-19）：按用户“只保留最终修改的源码”要求，已删除本轮三份 root-power 项目缓存中的原始日志、私密手机备份、抓包/截图/测试脚本、测试结果附件、旧包及最终 APK 副本；同时清理 Root 构建输出、Dart/Gradle/Kotlin 项目缓存、插件生成清单、root/dist 测试产物及工作区 dist/03 的 Root APK/校验文件。下文日志/备份/APK 路径与摘要仅作历史验证记录，文件现已删除。最终源码、正式测试、本文和 LOCAL_CHANGES.md 保留；签名、工具链、共享构建依赖及手机已安装 App 和正常代理运行数据未改动。两机已知测试临时目录及 XML 复查无残留。

## 审查发现与实现

原实现 Android START_STICKY 前台服务每两秒查询 Root 状态、保存运行模式；查询会创建 su。Supervisor 每两秒检查进程、热点及日志，清理失败无限重试。主页跨标签采样，配置编辑页未完全跟随应用生命周期暂停。

现链路：App / 快捷磁贴 → 临时 ProxyTProxyService → 经过身份校验的 Root Supervisor → 直接子进程 Mihomo。服务返回 START_NOT_STICKY，队列完成后 stopForeground / stopSelfResult；onDestroy 不停止代理。Supervisor 负责安装私有规则、阻塞 wait、退出清理。另有阻塞 FIFO 的日志读取 Shell，按写入字节数限额轮转；它没有定时工作。没有新增 Android 常驻服务或开机脚本。

启动和控制保留串行保护；停止取消此前排队的启动，后续明确启动仍可执行。配置写入与启动 admission 互斥。冷启动、界面恢复和磁贴展开对启动/停止等过渡状态也做一次 Root PID / UID / start tick / cwd / cmdline 校验；已确认守护死亡时忽略陈旧过渡标记；Root 授权失败拒绝修改。可见页面后续使用有缓存的本机端口探测，绝不每秒创建 su。端口探测只用于界面提示，所有修改边界仍做 Root 身份验证。旧 Supervisor 使用原 stop 文件协议，下次手动重启迁移，运行中不重写旧脚本。

TERM / INT / HUP 为明确停止；USR1 通知共享策略变化。信号目标在发送前验证完整身份；命令行读取有时限，发送后只按已捕获的 UID/PID/start tick 等待，避免读取正在退出的 Android 进程而卡住。Mihomo 正常或异常退出唤醒 wait。控制信号通过带 busy 标志的串行分派处理，更新期间到达的停止请求先排队再处理，不会在下一次 wait 前丢失；EXIT 收尾忽略重复控制信号，避免清理中断。规则清理每次请求最多四次，退避 0 / 1 / 2 / 4 秒，每次上限 10 秒；失败写 cleanup_failed，存活内核继续工作并阻塞等待下一次显式停止。启动失败和内核退出均执行有界清理；下一次明确启动或恢复操作先停止经过身份校验的孤立共享监控，再清理私有规则，最后结束孤立内核和日志进程。

共享禁用或选择为空时不启动监控。启用后 netlink 事件与 60 秒兜底覆盖 Android Tethering 事件遗漏；界面策略改变直接通知 Supervisor。保留显式接口白名单与局域网/DNS规则。快照不变时不写规则；快照变化也只提交实际不同的表。关闭 IPv6 时不采集 IPv6 地址，因此 IPv6 地址变化不会触发无意义更新。事件监控与兜底进程仅在共享启用期间存在。

主页状态每三秒仅在主页面可见时刷新，流量每秒仅首页标签且代理运行时采样；进入后台或完整子页面即暂停。配置编辑页仅可见时刷新状态。没有新增主动测速、健康检查或订阅更新任务；原用户配置相关任务仍由 Mihomo 自己执行。

## 文件说明

路径均相对 root/：

| 文件 | 改动与原因 |
| --- | --- |
| android/app/src/main/kotlin/com/liuyihtu/mclash/root/ProxyTProxyService.kt | 临时启停操作服务；非 sticky；串行队列；销毁不清理代理 |
| 同目录 RootOperationState.kt | 可测试的启停取消、排队启动计数及持久阶段与状态提示 |
| 同目录 RootProcessIdentity.kt | PID、Root UID、启动时间、物理目录及完整命令身份校验 |
| 同目录 RootSupervisor.kt | 阻塞 wait、信号控制、有界清理、共享按需事件监控、阻塞日志限额 |
| 同目录 MihomoBridge.kt | 脚本生成、冷连接、状态缓存、身份校验控制、孤立进程恢复、旧协议兼容；已确认守护死亡时端口提示不可覆盖校验结果 |
| 同目录 RootHotspotMonitor.kt | 原子快照与确认、按表去重、IPv6 关闭时避免采集；在去重前检查热点加速过滤器 |
| 同目录 HotspotOffload.kt、HotspotRules.kt | 所选共享接口的 Android tethering 加速兼容；安装前日记、ifindex 与完整身份校验、有界清理；保留系统过滤器 |
| android/app/src/test/…/HotspotOffloadTest.kt | 加速识别、幂等、优先级/其他过滤器冲突、接口复用、清理失败、安装中断和旧系统回归 |
| 同目录 RootShell.kt | Root 命令本身超时，避免只结束 su 客户端后命令继续执行 |
| 同目录 MainActivity.kt | 恢复只连接；状态查询移至工作线程；配置写入和启动互斥 |
| 同目录 CoreUpdater.kt | 更新操作使用独立内核状态，不依赖服务常驻标志 |
| 同目录 MclashTileService.kt | 展开时一次校验，App 未打开仍可启停 |
| android/app/src/main/AndroidManifest.xml | 显式 stopWithTask=false，说明前台服务仅用于启停 |
| lib/main.dart、lib/shared/page_visibility.dart | 页面可见性观察器 |
| lib/pages/home_page.dart、config_editor_page.dart | 可见性与生命周期控制采样；相关页面才查询控制器模式 |
| android/app/src/test/…/RootSupervisorTest.kt | 真实子进程 wait、信号、崩溃、启动失败、有限清理重试、共享启停、身份拒绝 |
| android/app/src/test/…/MihomoRecoveryTest.kt、RootHotspotMonitorTest.kt、RuntimeEditsTest.kt | 更新身份、规则变化和并发回归覆盖 |
| test/live_controls_test.dart、config_editor_test.dart、draft_preservation_test.dart | 前后台及页面采样、原编辑/草稿断言保持 |

## 真机检查方法

先备份已安装 APK、files 和 shared_prefs，保持私密，不输出订阅或配置内容。安装使用同一签名的更新包，禁止为解决签名冲突直接卸载。

以下命令在 `adb shell` 后进入的交互 Shell 内执行；Root 命令再用 `su`，避免 adb 多层引号误将命令放在普通 Shell：

```sh
su
D=/data/user/0/com.liuyihtu.mclash.root/files/mihomo
cat "$D/ready" "$D/protocol"
S=$(cat "$D/supervisor.pid"); C=$(cat "$D/core.pid")
cat /proc/$S/cgroup /proc/$C/cgroup
ps -A -o USER,PID,PPID,NAME,ARGS | grep -E 'mihomo|supervisor.sh|sharing-watch|log-writer'
dumpsys activity services com.liuyihtu.mclash.root
```

启动完成后应为 ready / protocol 2，Supervisor 和内核不在 App UID 的冻结分组，操作服务消失；共享关闭时无 sharing-watch、ip monitor 或 60 秒 sleep。Supervisor 仅有内核与阻塞日志读取子进程。观察 `/proc/$S/stat`、`/proc/$S/wchan` 与子进程列表，跨时间比较；不要把 Mihomo 自身网络任务误算为 Supervisor 周期轮询。

回桌面、划掉最近任务、`am kill com.liuyihtu.mclash.root`、`am force-stop com.liuyihtu.mclash.root` 分别验证 App PID 消失而 S/C 身份不变、TCP/UDP/DNS 继续；重新打开后不得重复启动内核。强制停止会限制 Android 组件调度，磁贴的恢复须实测且可能需先手动打开 App。

只在核对 `$C` 的 cmdline/start time 后对测试内核执行 `kill -KILL "$C"`；应触发 Supervisor 清理及 stopped。Android mksh 信号处理上下文中，成功分支必须显式 return 0，避免继承被中断 wait 的退出码。本次真机发现并修复此差异；回归同时检查内核与共享监控实际消失，不能仅依据 stopped 标记。

正常停止和异常退出后分别检查：

```sh
iptables-save | grep MCLASH_R_
ip6tables-save | grep MCLASH_R_
ip rule show | grep -E '^9000:|lookup 20230( |$)'
ip -6 rule show | grep -E '^9000:|lookup 20230( |$)'
ip route show table 20230
ip -6 route show table 20230
```

无匹配应为正常；不得清空整表。保留其他应用规则。再分别测试 TProxy/TUN、IPv4/IPv6、应用分流、节点切换、DNS、网络切换、热点/USB及其接口与地址变化；没有连接共享客户端时不能判定热点端到端通过。

## 边界与测量

SIGKILL 无法捕获；Supervisor 被单独强杀后，自动清理不保证。仅重新打开界面负责识别状态，不会自动清理孤立进程；下一次明确启动或恢复操作才执行身份校验和清理。Root 授权变化、SELinux、冻结器、系统强停策略和 Root 框架升级可能阻止清理或 cgroup 移动，需逐机验证。应用被卸载时不能承诺脚本仍可访问或自行清理；先停止再卸载。没有重型独立 watchdog 兜底，也不伪称覆盖这些不可控情况。

耗电需要断开 USB 充电，固定网络、信号、配置、Mihomo 版本、流量和温度，交替进行旧/新包多次待机与负载测量；同时采集整机电量、CPU 时间、唤醒和 Root 进程统计。Android App 电池页可能不把 Root 内核全部归到 App，不能据此计算省电百分比。本次功能检查不等于完成待机耗电测量。

## 首台设备验证结果（历史记录）

本地工具链 Flutter 3.44.9 / Java 17；未改变 CI Flutter 3.32.8 配置，未宣称已在 CI SDK 上运行。

| 检查 | 实际结果 |
| --- | --- |
| 格式、Flutter 静态分析 | 通过；分析 No issues found |
| Flutter 全量 | 225 项通过 |
| Kotlin / Shell 全量 | 97 项通过，失败/错误/跳过均为 0；包含 TProxy/TUN 模拟规则生命周期 |
| 03 全流程 | 依赖、格式、分析、Flutter、Kotlin、ARM64 Release、APK ZIP 与签名校验通过 |
| 六轮 TProxy 正常启停 | 每轮确认内核 PID 和共享监控 PID 真正消失、私有链/规则/20230 路由无残留；停止含检查约 1.85–2.39 秒 |
| App 进程被回收/强制停止 | App PID 消失，Root 进程身份不变；百度 HTTPS 200、国外 HTTPS 204 继续；重新打开连接同一内核，操作服务不常驻 |
| 无共享待机 | 临时关闭运行策略并恢复；App 无 PID/前台服务，Supervisor 仅有内核和阻塞日志读取子进程；30 秒自身及已结束子进程 CPU 增量均 0 tick |
| Mihomo 异常退出 | App 不在运行时 SIGKILL 测试内核，Supervisor 清理私有规则并停止共享监控，状态 stopped |
| 主页开关 | 冷恢复忽略已死亡守护的残留 stopping 标记；实际点击停止后显示启动按钮、实际点击启动后显示停止按钮；失败仍运行的 Widget 回归通过 |
| DIRECT 网络复测 | 保留用户国内组 DIRECT 选择；百度 HTTP/HTTPS、系统解析、TCP/UDP DNS 正常；IPv4 DNS 重定向及 IPv6 回环 DNS 均收到有效应答 |
| 安装与配置 | 原 APK / 私密数据已备份；同签名覆盖安装；手机已安装 APK 与 dist/03 交付 APK SHA-256 一致；保留最新 DIRECT 选择、原 TProxy / IPv6 / 共享设置 |

测试设备：魅族 20、Android 13、KernelSU 系 Root（su SELinux context 为 ksu）。最新日志位于本项目 `.build-cache/root-power-20261018/logs/local-root-20261018-213842-579495.log`，原始设备证据位于同缓存的 `device/`，只保存在本地。

中间包发现的 `/proc/cmdline` 卡住、更新期间控制信号延后、mksh 裸 return 导致漏停及陈旧主页状态已修复并复验；中间测试失败和被替代的日志保留，不作为最终成功依据。自动化没有删除或跳过失败断言。

本机未完成的项目：用户明确说明设备不支持 TUN，因此没有切换到 TUN；控制中心 ADB add-tile/click-tile 未实际添加磁贴，未触发磁贴服务，不能将冷磁贴启停列为真机通过，需在支持的系统上手动添加后验证。热点客户端及 Wi-Fi/USB 切换、外部 IPv6 网络、分应用完整矩阵、独立划掉最近任务/冻结测试、Magisk/APatch 兼容性和长期待机功耗仍需专项测量。腾讯站点本次返回 HTTP 501，未列为网站访问成功，未擅自更改相关节点或规则。

交付 Root APK：`dist/03/Mclash-root-android-2.3.2+13-arm64-v8a-release.apk`（相对工作区），SHA-256 `56b51aa711da3e203a094e527d870cfe37ebdc1e3077adf0ea8a4a106cb48c35`；旁边有 `.apk.sha256`。普通 Android VPN 与 Windows 未在本次重新编译。未提交、推送、创建 PR 或启动 GitHub Actions。


## 新手机 TUN 快速验证（2026-10-18）

小米 25113PN0EC / Android 16 / KernelSU 3.3.1，按用户要求缩小为当前 TUN / mips 的快速检查，未扩展为四栈矩阵。原安装 build 14、旧 Supervisor；先私密备份 APK、files 和 shared_prefs，正常停止旧代理且确认规则清空。两包签名一致。系统拒绝降级至 build 13，因此通过 03 副本既有 MCLASH_BUILD_NUMBER=14 仅在临时副本设置构建号；仓库 pubspec 保持 2.3.2+13。

实际通过：TUN mclash0 / Mips 启动，操作服务结束；HTTP 204、百度 HTTPS 200、远端及本机 TCP / UDP DNS（含 IPv6 回环）、UDP STUN 均收到有效响应；force-stop App 后 App PID 消失、Root Supervisor / Mihomo PID 和启动时间不变、无前台 Service、HTTPS 与 UDP DNS 继续；重开连接原内核、主页显示停止按钮；正常停止和经身份复核后 SIGKILL 内核，均确认原进程、TUN 接口、私有防火墙及策略路由无残留。最后恢复原 TUN / mips / IPv6 / 共享接口设置并运行，配置文件逐字节摘要及相关持久设置与备份一致。

证据保存在本项目 .build-cache/root-power-tun-20261018/device/；私密备份不纳入源码。这里只验证当前 mips，不代表 system / mixed / gvisor、本机磁贴、热点客户端、外部 IPv6或真实待机耗电已验证。此次手机检查未发现需要新增源码修复的问题。为核查进程及路由，用户临时授权了 Shell UID 2000 Root。

03 全流程最终通过：225 项 Flutter、Kotlin/Shell 全量、静态分析、ARM64 Release 与签名校验；日志 local-root-20261018-220236-704953.log。交付 dist/03/Mclash-root-android-2.3.2+14-arm64-v8a-release.apk 及校验文件，已安装包与交付包 SHA-256 一致：`2005a192a190b895fb69410da668365308306d6cfd516a53cd25b64772c52c06`。源码摘要未改变，未提交、推送或触发 GitHub Actions。


## 双机完整验证与热点加速修复（2026-10-18 至 2026-10-19）

设备：小米 25113PN0EC / Android 16 / KernelSU 为代理主机；魅族 20 / Android 13 为热点客户端。两台均使用各自明确的 ADB serial，不把客户端自身的代理当作热点成功。新证据、私密备份及测试脚本保存在本项目 .build-cache/root-power-full-20261018/。

四种 TUN 协议栈 mixed / system / gvisor / mips，以及 TProxy 均已实测 HTTP、HTTPS、TCP/UDP DNS、IPv6 回环 DNS、UDP STUN及停止后的内核、TUN 接口、私有规则清理。IPv6 关闭的第一次失败与所选 IPv6 节点有关；用户将国内组改为 DIRECT 后同用例全部通过，保留最新 DIRECT 选择。App cgroup 冻结、身份核对后的 App SIGKILL、force-stop 后原 Supervisor / Mihomo 身份不变且国内外 HTTPS、UDP DNS 继续；重开恢复主页状态。小米 ROM 的 am freeze 自身抛 NullPointerException，am kill 没有真正结束 App，分别如实记录并改用仅针对本 App 的内核冻结和 PID/UID/start tick/cmdline 核对后终止，未修改全局冻结设置。

手机真实 Android Shell 上还执行了隔离 Supervisor 测试：仅替换模拟内核、监听条件及空安装/清理脚本，未操作网络规则。正常停止、退出 0、退出 42、SIGKILL 内核均清理并退出；清理失败四次后保留内核、三秒内不再重试，显式重试后成功。

热点客户端首次 IPv6 HTTPS 超时。抓包显示 SYN/SYN-ACK 经 TUN，而后续 ACK/TLS 被 Android tether upstream tc eBPF 快速路径旁路；临时独立过滤器的 A/B 检查使 IPv6 百度 HTTPS 200、国外 HTTPS 204 立即恢复，撤销后系统原过滤器摘要完全一致。这是本轮新增修复，未把失败测试计为通过。

新增 HotspotOffload.kt：仅在用户明确选择、Android 当前报告为 Tethered 的接口上，发现系统 tether upstream 加速后安装 Mclash 自有 protocol all / pref 1 / handle 0x4d43 的一条 cBPF RET TC_ACT_OK。其含义见 [iproute2 tc-bpf 手册](https://kernel.googlesource.com/pub/scm/network/iproute2/iproute2-next/+/refs/heads/main/man/man8/tc-bpf.8)。它让包继续进入正常协议栈和原有 Mclash 规则，无新用户空间服务；不删除系统 BPF、不改全局 offload 设置、不接管未选接口。安装前记录接口 ifindex；拒绝其他规则的优先级/身份冲突；仅按日记和完整过滤器指纹删除，接口复用不能误删，清理失败保留日记以供有界重试。旧系统无该加速时不安装过滤器。共享开启期间重查过滤器，稳定时不重写日记。

RootHotspotMonitor.kt 在快照去重前同步自有过滤器，HotspotRules.kt 将其纳入清理；RootHotspotMonitorTest.kt 使用隔离 tc 模拟器，新增 HotspotOffloadTest.kt 覆盖接口选择、幂等、冲突、接口复用、失败清理、安装中断和旧系统路径。7 项定向测试通过；增加了其他 tc 过滤器在安装后出现时撤销自有规则、绝不绕过它们的回归。共享需要系统 tc；存在异常优先级冲突或工具缺失时明确失败，不替换其他规则。共享开启时对应流量经过正常协议栈，不使用该接口的 tether 快速转发；高流量下的 CPU/吞吐影响尚未量化。关闭共享或停止代理后撤销自有过滤器，Android 原加速过滤器继续保留。


### 双机最终检查覆盖

| 检查 | 实际结果 |
| --- | --- |
| 五模式热点端到端 | mixed / system / gvisor / mips 与 TProxy，各模式客户端 HTTP、国内/国外 HTTPS、TCP/UDP DNS、UDP STUN、LAN ping 11 项通过；每次停止删除自有 tc 过滤器、保留 Android 原过滤器 |
| 热点生命周期 | AP 关闭移除自有过滤器、重新开启按新 ifindex 安装；内核身份不变，客户端重新连接已保存热点后 11 项通过 |
| 实际 Wi-Fi / 蜂窝切换 | 用户连接 Wi-Fi 后，wlan0 → rmnet → wlan0 三阶段主机 HTTPS 200、热点客户端各 11 项通过；Supervisor / Mihomo PID 与启动时间不变；最终恢复 Wi-Fi 开启、热点开启 |
| App 生命周期 | 实际划掉最近任务并确认 App PID 消失、cgroup 确认冻结、身份核对后终止 App、force-stop 后原内核继续；重新打开恢复同一内核及主页状态；无常驻 ProxyTProxyService |
| 冷磁贴与并发 | 无 Flutter Engine 的冷磁贴启动/停止通过；重复 START 不重复建内核，START/STOP/START 有序收敛；仅选应用但列表为空被明确拒绝、无规则残留 |
| 应用分流 | 真正浏览器 UID 的仅选代理和排除代理访问通过；分别命中私有 MARK / RETURN 计数；恢复原空排除列表 |
| 节点与 IPv6 | Controller 切换后读回并恢复原选择；IPv6 关闭时 IPv4/默认 HTTPS 通过，直接 IPv6 请求命中共享拒绝规则，随后恢复 IPv6 开启 |
| 异常退出 | App 不在时终止经过身份复核的 Mihomo，Supervisor、内核、共享监控、日志读取及私有链/路由/TUN/自有 tc 均清理；系统 tc 保留，重开可启动 |
| 无共享待机观察 | 关闭共享、force-stop App，Supervisor 只有内核和阻塞日志读取两个直接子进程；60 秒自身及已结束子进程 CPU 增量均为 0 tick；已恢复共享，不据此声称电池耗电百分比 |

配置核对保留用户本轮主动将国内组改为 DIRECT 的三行差异及更新时间；其余订阅文件内容不变，原 TUN / mips / IPv6 / 共享 wlan2 与空应用排除设置恢复。客户端自身 Root 代理保持测试前的停止状态。测试没有覆盖用户同期修改，最新包同时包含本地另一项“Root 移除隐藏多任务卡片”源码改动；原先有关保留该入口的历史记录只描述当时快照。

原始证据：本项目 .build-cache/root-power-full-20261018/，含 wifi-handover-console.log、device/wifi-cellular-handover.json、hotspot-matrix-console.log、hotspot-restart-console.log、final-lifecycle-console.log、app-filter-browser-console.log 和各客户端 JSON。中间脚本因环境变量缺失、输入法候选遮挡、等待系统联网或断言前提错误而失败的日志保留；仅修正测试步骤并重跑后的实际结果列为通过。

最近任务首次检查为用户锁定，未擅自改动。随后用户自行取消锁定，实际只上划 Mclash Root 卡片并确认从列表消失；App PID 随之消失，Root 两进程身份不变，无操作服务，客户端 11 项全部通过；重开主页正确运行。证据 recents-removal-console.log、device/recents-swipe-attempt.json、device/recents-removed-network.json。

仍未验证：断开 USB 的长期耗电、Magisk / APatch 真机、USB / 蓝牙共享及其与 Wi-Fi 共享的切换、Root 授权撤销后的设备行为、不同 ROM 强停/冻结策略。没有编造省电比例，也没有把当前两台 KernelSU 的结果扩展为所有设备兼容。


### 收尾发现的孤立内核状态修复

实际强杀经过 PID / UID / start tick / cwd inode / 完整命令校验的 Supervisor 后，Mihomo 仍可保留监听端口。发现 App 恢复虽然确认守护死亡，后续端口采样仍会把主页覆盖为“运行中”。修复 MihomoBridge.kt 的 isRunning / probeRunning 缓存判断，已知 owner=false 时禁止端口重置；RootOperationState.kt 的状态优先级同步修正，RuntimeEditsTest.kt 覆盖 ready / stopping 陈旧标记加开放端口，以及显式启停期间的优先级。没有增加任何定时 su。之前“守护死亡但端口仍开”返回 running 的旧断言按实际恢复行为更新，其他断言保留。

该故障最初的测试脚本对 /data/user/0 与 /data/data 的字符串路径比较未能通过身份校验，未执行信号；改为实际设备号/inode 校验后才执行。真正触发后保留了主页状态失败证据，并据此修改源码；不是将此产品缺陷作为脚本误差跳过。


## 最终构建与交付记录（2026-10-19；产物随后已清理）

最终 03 副本全流程通过：格式 93 个文件无变化、Flutter 静态分析 No issues found、Flutter 224 项、Kotlin/Shell 102 项（失败/错误/跳过均为 0）、ARM64 Release、ZIP、签名及 SHA-256 校验。Flutter 从前一轮 225 变为 224 是同期 Root 隐藏任务入口移除后的测试集合变化；本轮状态修复是在 RuntimeEditsTest 原用例内补充断言，未删除测试以绕过失败。依赖工具已有的 Kotlin 版本即将弃用提示、overridePendingTransition 和测试泛型转换编译警告仍保留，没有跳过分析或测试。

最终日志：.build-cache/root-power-20261018/logs/local-root-20261019-003431-1477988.log。原生 XML 保留于 .build-cache/root-power-full-20261018/orphan-status-native-results/，汇总 build-result.json；源码与 latest-build-source-sha256.json 的全部摘要一致。03 副本仅调整工作区/日志路径；使用既有 MCLASH_BUILD_NUMBER=14 环境参数对临时副本设置构建号以兼容原装 build 14，仓库 pubspec 仍为 2.3.2+13，签名材料、依赖/分析/全测试/打包/签名流程不变。

交付并已同签名覆盖安装：工作区 dist/03/Mclash-root-android-2.3.2+14-arm64-v8a-release.apk 及同名 .apk.sha256。SHA-256：`a0178795409a095bff8f085938bbeda65787dd24588a928823e364164aacde4f`；从手机再次拉取 base.apk 的摘要与交付包一致。

最终包真机复验：正常停止旧实例无私有规则/TUN 残留；启动后主页运行状态正确、无 ProxyTProxyService、设置中无已移除的隐藏任务入口。实际强杀 Supervisor 后主页显示可启动；下一次明确启动回收旧内核和旧辅助进程，仅生成一个新内核，热点客户端 11 项通过（orphan-recovery-console.log）。再次 force-stop 最终 App，App PID 消失、Root 两进程身份不变、无操作服务、客户端 11 项通过；重开仍连接同一内核并正确显示停止按钮（final-checks-console.log、device/final-device-checks.json）。单独划掉最近任务及 Wi-Fi / 蜂窝切换的前述用例已通过，相关生命周期/网络实现与最终包相同；最终包追加了孤立内核状态判断与同期任务入口移除。

最后状态：主机 TUN / mips / IPv6 开启、共享 wlan2 开启、Wi-Fi 已连接且热点出口 wlan0；客户端自身 Root 代理仍停止、连接主机热点。最新 DIRECT 的两份配置/订阅文件与本轮最终基准逐字节一致；Root/共享/应用分流/当前配置/运行模式持久设置逐项一致。临时添加的 Root 磁贴已移除，原普通 VPN 磁贴保留；两机仅清除本轮已知的测试目录和 XML，未清理其他任务或文件。本项目本轮两个空闲 Gradle 守护已结束，未停止其他项目守护。

2026-10-19 再次 git ls-remote 确认 GitHub main 为 c417662b0c39cb0d2724e3c6873cc4e98a0422fb。仅本地修改、构建和手机测试；未提交、推送、创建 PR 或触发 GitHub Actions。Shell UID 2000 的 KernelSU 权限由用户临时开启，测试未更改该授权；测试完成后可在 KernelSU 撤回 Shell 授权，Mclash 自身 Root 授权仍单独保留。
