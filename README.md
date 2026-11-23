# Mclash

基于 Mihomo 和 Flutter 的代理客户端，支持 Android VPN、Android Root 和 Windows。

## 支持平台

| 版本 | 运行方式 |
| --- | --- |
| Android VPN | 无需 Root，通过系统 VPN 接管流量 |
| Android Root | 支持 TUN / TProxy、分应用代理和热点共享 |
| Windows | 支持系统代理和 TUN，通过独立服务管理内核 |

## 下载

前往 [Releases](https://github.com/liuyi-htu/Mclash/releases/latest) 下载对应平台的安装包，提供 SHA-256 校验文件。

Android VPN 与 Root 版可以同时安装。项目不内置机场订阅，请自行导入 YAML 配置或添加订阅。

## 功能

- 机场订阅管理、手动节点导入与节点测速。
- 代理组、规则、DNS、Host 和链式节点设置。
- 运行中保存配置，下次启动代理时应用。
- 浅色与深色主题、内核更新和本地离线网页面板。

## 构建

构建环境、签名配置与本地构建命令见 [构建与开发](docs/BUILD.md)。

GitHub Actions 仅手动触发：在 **Actions → Build Mclash clients → Run workflow** 中选择平台、版本和构建号。全部平台构建成功后发布 Release。

## 源码

- [android/](android/)：Android VPN 客户端。
- [root/](root/)：Android Root 客户端。
- [windows/](windows/)：Windows 客户端、系统服务与安装程序。
- [assets/](assets/)：共用资源与默认配置。

## 开源许可

Mclash 使用 [GPL-3.0](LICENSE) 许可证。

第三方组件及资源遵循各自的许可证，详见 [第三方许可说明](THIRD_PARTY_NOTICES/)。
