# Dotfiles

[English](README.md) | [简体中文](README.zh-CN.md)

由 [chezmoi](https://www.chezmoi.io/) 管理的个人 Arch Linux 配置，适用于桌面、
笔记本和无图形设备。

Bash 与 Zsh 共享登录环境；模块化 Niri 桌面可选择 custom 组件组合或
DankMaterialShell，并包含 LazyVim、Git、SSH 和 Pi 配置。机器能力决定部署
哪些目标；凭据、下载的软件包与应用运行状态不进入 Git。

## 开始使用

按照[快速开始](docs/quickstart.md)准备依赖、初始化机器数据、验证源码，并接管
审阅过的目标。初始化不会应用配置，也不会安装系统软件包。

已经在使用本仓库？

- [更新或添加配置](docs/usage.md)，避免覆盖本机状态。
- [选择机器能力](docs/configuration.md)，包括桌面和 SSH 配置档案。
- 导入已有文件前，先[了解所有权](docs/how-it-works.md)。
- 预览凭据相关文件或加密目标前，先阅读[安全说明](docs/security.md)。

## 配置你的环境

| 领域 | 阅读入口 |
|---|---|
| Shell、XDG 路径与用户级 Node.js | [Shell 环境](docs/shell.md) |
| 固定版本的 Oh My Zsh 与 Powerlevel10k | [Zsh 依赖](docs/zsh.md) |
| 字体、应用、locale 与密钥环 | [桌面](docs/desktop.md) |
| Niri custom/DMS 选择与迁移 | [桌面方案](docs/desktop-shells.md) |
| 可选的 iPhone 通知与剪贴板 | [Tether](docs/tether.md) |
| 模型、通知、扩展与代理 | [Pi](docs/pi.md) |
| 可选的本地代理服务，不启动 Web UI | [Paseo](docs/paseo.md) |
| 共享的代理技能 | [Skills](docs/skills.md) |
| 提交身份与 SSH 认证 | [Git](docs/git.md) 与 [SSH](docs/ssh.md) |

全部指南与参考资料见[文档索引](docs/index.md)。专题文档使用英文。

## 开发与验证

在 chezmoi 源码目录执行：

```sh
./tests/check-source.sh
git diff --check
```

检查保持离线；部分渲染检查需要对应工具已安装。它们不会安装依赖，也不会把
配置应用到你的 HOME。[开发指南](docs/development.md)列出依赖、专项检查和
跳过条件。编码代理应阅读 [AGENTS.md](AGENTS.md)。

将本仓库视为公开仓库。禁止提交明文凭据、私钥或运行状态。发布前需单独执行
[公开仓库安全流程](docs/publication.md)。
