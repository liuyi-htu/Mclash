# Mclash for Windows

Mclash 是一款基于 Flutter 开发的 mihomo Windows 桌面客户端，通过独立的
`Mclash` Windows 系统服务管理代理内核。

## 下载

请从 [Releases](https://github.com/liuyi-htu/Mclash-for-windows/releases)
下载最新版安装包：

```text
Mclash-Windows-Setup-1.0.2.exe
```

默认安装目录为 `D:\Program Files\Mclash`。配置文件、机场订阅、日志、运行状态
和 GeoIP/域名数据库均保存在安装目录下。卸载时会停止并删除系统服务，同时清理
应用文件及运行数据。

## 功能

- 导入本地 mihomo/Clash YAML 配置
- 导入并更新机场订阅
- 启动、停止和查看 mihomo 运行状态
- 在常规设置中控制 `Mclash` 系统服务开机自启
- 在常规设置中控制 IPv6 和局域网绕过
- 对比官方版本并更新 mihomo 内核
- 内置 sing-box 常用 GeoIP/GeoSite 二进制规则集
- 自动下载并校验 GeoSite、GeoIP 和 Country 数据
- 通过浏览器打开代理面板
- 限制为单实例运行

## 使用

1. 安装并启动 Mclash。
  2. 点击右上角按钮，导入本地配置或机场订阅。
3. 选择需要使用的配置。
4. 点击“启动代理”。
5. 如需开机自动启动系统服务，请在“常规设置”中开启“开机自启”。

mihomo 外部控制接口固定为：

```yaml
external-controller: 127.0.0.1:9090
```

代理端口仍以导入配置中的 `mixed-port`、`port` 或 `socks-port` 为准。
默认配置仅监听本机并关闭局域网代理；系统代理模式会绕过本机和常见私有网段。
Mclash 启用系统代理前会保存当前登录用户原有的代理设置，并在停止代理或切换到
TUN 模式时恢复。
IPv6 默认关闭，局域网绕过默认开启；修改后会同步更新当前运行配置。
自动生成的 `default.yaml` 可以直接删除；删除后切换运行模式也不会再次自动创建，
如需恢复请重新导入配置。

## 本地构建

构建环境：

- Windows 10 或更高版本
- Flutter（启用 Windows 桌面支持）
- Go
- Visual Studio C++ 构建工具
- Inno Setup 6

运行：

```powershell
.\scripts\build-windows.ps1
```

构建脚本会从远端下载默认 mihomo 配置，并下载、校验最新的官方 mihomo 内核与 GeoSite/GeoIP/Country 数据，
执行 Dart 和 Go 检查，并生成：

```text
installer\Output\Mclash-Windows-Setup-1.0.2.exe
```

## GitHub 构建

推送 `v*` 标签后，GitHub Actions 会在 Windows Runner 上自动构建安装包，并将
安装包及 SHA-256 校验文件发布到 GitHub Releases。

## 项目结构

- `mclash`：Flutter Windows 客户端
- `windows-service`：Windows 服务管理器与 mihomo 更新程序
- `installer`：Inno Setup 安装脚本
- `scripts`：Windows 构建脚本
- `windows-package`：构建过程中使用的打包暂存目录

## 许可证

本项目依据 [GPL-3.0](LICENSE) 许可证开源。
