# Dotfiles

[English](README.md) | [简体中文](README.zh-CN.md)

这是一个由 [chezmoi](https://www.chezmoi.io/) 管理的个人 Arch Linux
配置仓库。它支持 Bash 或 Zsh、图形化 Niri 设备、无图形设备、Neovim、Git
和 Pi，同时确保凭据与应用运行状态不会进入 Git。

## 主要特性

- 在 `chezmoi init` 时按机器能力选择配置。
- Bash 与 Zsh 共享公共登录环境，交互行为仍由各自单独管理。
- 用户会话使用简体中文，交互式 Shell 则使用完整的英文 locale。
- 比例界面使用 Adwaita Sans，终端使用 JetBrainsMono Nerd Font Mono，
  状态栏使用其完整宽度的 Nerd Font 变体；Noto 字体提供 CJK、符号与
  Emoji 回退。
- Niri 使用模块化配置和可选择的显示器配置档案。
- 为 Matugen 与 Waypaper 提供初始状态，同时避免后续 apply 覆盖应用生成值。
- LazyVim 配置包含根据经过验证的本地插件检出重建的锁文件。
- Pi 模型与 Telegram 凭据通过 `rbw` 从 Bitwarden 获取。
- OpenSSH 使用经 age 加密的公钥选择器与主机元数据，客户端私钥由
  Bitwarden 中的 `rbw-agent` 使用；Git 身份元数据同样经过加密。
- 递归 `rm` 会转移到桌面回收站，并拒绝操作受保护的 XDG 与 Pi 根目录。

## 仓库结构

```text
.
├── .chezmoi.toml.tmpl       # 本机数据与秘密后端
├── .chezmoiignore           # 条件化目标和状态排除规则
├── dot_config/
│   ├── shell/, bash/, zsh/  # Shell 环境与交互模块
│   ├── git/, nvim/          # Git 身份与 LazyVim
│   ├── environment.d/       # locale、图形输入法与 rbw-agent socket
│   ├── fontconfig/, gtk-*/  # 用户字体别名与 GTK 默认值
│   ├── niri/, waybar/       # Niri 桌面会话
│   ├── kitty/, fuzzel/      # 终端与启动器
│   ├── mako/, matugen/      # 通知与生成的主题配色
│   ├── waypaper/            # 壁纸集成
│   └── private_pi/agent/    # 使用私有权限的 Pi 声明式配置
├── private_dot_ssh/         # SSH 配置、公钥选择器与 authorized_keys
├── .chezmoitemplates/ssh/   # SSH 公钥的规范来源
├── dot_local/bin/           # 用户命令，包括安全 rm 包装器
├── scripts/                 # 仅供源码侧使用的 age identity 工具
├── tests/                   # 离线源码与渲染检查
├── docs/                    # 各组件操作说明
└── AGENTS.md                # 编码代理的仓库操作规范
```

chezmoi 的源码属性是本设计的一部分：

- `dot_` 生成前导点；
- `private_` 强制使用私有权限；
- `executable_` 设置可执行权限；
- `create_` 仅在目标不存在时创建；
- `modify_` 转换目标并保留指定的已有状态；
- `.tmpl` 文件使用本机数据渲染。

`README*`、`AGENTS.md`、`docs/`、`scripts/` 与 `tests/` 仅用于源码仓库，
不会安装到目标 HOME。

## 所有权与安全边界

- **Git**：保存可复现配置、模板、固定版本、秘密引用，以及经 age 加密的
  SSH/Git 身份元数据。
- **Bitwarden（`rbw`）**：保存日常运行凭据，以及由 `rbw-agent` 使用的
  SSH 客户端私钥。
- **age**：仅用于确实需要版本化的静态秘密文件。
- **各台机器本地**：保存 GPG 私钥、SSH 主机信任与本机扩展配置、缓存、
  历史、数据库、会话、Pi 登录/信任状态以及下载的软件包。

即使远端仓库是私有的，也要把本仓库视为公开仓库。禁止加入凭据、递归导入
`$HOME` 或 XDG 根目录，也不要提交恢复备份。

Pi 模型 provider 保存的是命令引用：

```json
"apiKey": "!rbw get 'pi spiredive api key'"
```

Telegram 扩展自身不支持解析命令，因此 chezmoi 会将 Bitwarden 中的值渲染到
权限为 `0600` 的目标文件。不要显示未过滤的 Pi diff。`--skip-secrets`
只会跳过秘密模板，不会遮盖目标文件里已经存在的明文凭据，也不会排除原生
加密源码。广泛预览时应同时使用 `--exclude=encrypted`。

## 机器配置档案

`.chezmoi.toml.tmpl` 会在本机 chezmoi 配置中初始化以下非秘密数据：

| 键 | 可选值 | 作用 |
|---|---|---|
| `role` | `desktop`、`laptop`、`server` | 机器角色元数据 |
| `shell` | `zsh`、`bash` | 选择一套 Shell 专属配置 |
| `graphical` | 布尔值 | 启用图形应用配置 |
| `niri` | 布尔值 | 启用 Niri、Waybar 及 swayidle 所有权转移 |
| `niriOutputProfile` | `auto`、命名档案 | 选择渲染后的显示器配置 |
| `work` | 布尔值 | 工作设备元数据 |
| `sshAgent` | 布尔值 | 启用 rbw SSH 客户端和公钥选择器 |
| `sshInboundIdentity` | `none`、`private`、`uni` | 选择 `authorized_keys` 所有权 |

显示器硬件未知时请选择 `niriOutputProfile = "auto"`。机器数据中禁止存放凭据。

## 前置依赖

在 Arch Linux 上安装仓库级工具：

```sh
sudo pacman -S --needed git chezmoi age rbw openssh python bash zsh glib2
```

完整源码验证需要 Bash 和 Zsh；实际运行时只需要所选的 Shell。还需确保已安装
`neovim` 和 `less`。Pi 与 Node.js 需要单独安装。图形环境依赖见
[docs/desktop.md](docs/desktop.md)；本仓库不提供系统级软件包引导安装。
`glib2` 提供安全 rm 包装器及其测试所需的 `gio` 命令。

宿主机必须已经生成 `en_US.UTF-8` 与 `zh_CN.UTF-8`。图形字体配置还需要
Fontconfig，以及 Adwaita、Noto、Noto CJK、Noto Symbols、Noto Color Emoji
和 JetBrains Mono Nerd Font 字体族；对应的 Arch 软件包见
[docs/desktop.md](docs/desktop.md)。

## 在新机器上初始化

### 1. 只初始化，不立即应用

私有仓库需要先配置 Git 访问，然后执行：

```sh
chezmoi init <repository-url>
cd "$(chezmoi source-path)"
```

不要添加 `--apply`。回答机器配置问题，并检查生成的
`~/.config/chezmoi/chezmoi.toml`。

### 2. 准备 Bitwarden 与 age

先配置本机 `rbw` 客户端，然后执行：

```sh
rbw register  # 新设备首次使用时按需执行
rbw login
rbw unlock
rbw sync
./scripts/restore-age-identity.sh
```

该脚本从 Bitwarden 条目 `chezmoi age identity` 恢复
`~/.config/chezmoi/age-identity.txt`，目录权限为 `0700`，文件权限为
`0600`。age 私钥绝不能进入 Git。

Pi 还依赖以下 Bitwarden 条目：

- `pi spiredive api key`
- `pi telegram bot token`
- `pi telegram chat id`

SSH 客户端机器还需要 [docs/ssh.md](docs/ssh.md) 所描述的原生 Bitwarden
SSH key 集合。首次配置时将解锁超时设为 15 分钟：

```sh
rbw config set lock_timeout 900
```

### 3. 准备应用的外部依赖

Pi 需要以下本地 checkout：

```text
~/Dev/local/omp/pi-extensions/pi-tree-continue
```

chezmoi 不会自动克隆它。还需要根据机器用途安装对应的 Shell、桌面、Neovim
和 Pi 依赖。

### 4. 验证源码

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
```

测试套件应保持离线。Pi 模板测试使用假的 `rbw`；安装了 `niri` 时，其配置会
渲染到隔离的临时 HOME 并接受验证。SSH 配置档案与公钥选择器使用生成的假
数据测试；显式可信检查还会验证真实 age 密文，但不会输出解密内容或访问
vault。safe-rm 测试会执行一次真实的 GIO 回收站往返，并在完成后恢复测试项。

### 5. 审阅并应用

对于没有既有 Pi 明文凭据配置的新机器：

```sh
chezmoi status --skip-secrets --exclude=encrypted
chezmoi diff --skip-secrets --exclude=encrypted
chezmoi apply --interactive --skip-secrets --exclude=encrypted

rbw unlock
chezmoi apply \
  "$HOME/.config/pi/agent/extensions/pi-telegram-notify/config.json"

CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
chezmoi apply "$HOME/.gitconfig" "$HOME/.config/git"
chezmoi apply "$HOME/.ssh"
```

第一次 apply 会排除秘密模板；`rbw unlock` 后的定向命令会渲染私有 Telegram
配置，但不会把它显示在 diff 中。后续命令会单独验证并应用 age 加密的 Git
与 SSH 元数据；如果机器的两项 SSH 能力均关闭，则省略 SSH apply。

如果机器已经存在配置，应先备份，然后逐个组件接管：

```sh
chezmoi status --skip-secrets <target>
chezmoi diff --skip-secrets <sanitized-target>
chezmoi apply <reviewed-target>
```

不要 diff 可能包含明文密钥的既有 Pi `models.json`。请按照
[docs/pi.md](docs/pi.md) 中的直接脱敏流程处理。不要 diff 加密的 SSH
目标，否则会输出解密后的主机清单；请使用 [docs/ssh.md](docs/ssh.md)
中的可信检查与定向 apply。

应用完成后启动新的登录会话，并检查：

```sh
command -v rm
locale
fc-match sans-serif
fc-match monospace
chezmoi status --skip-secrets --exclude=encrypted
```

预期的 `rm` 路径是 `~/.local/bin/rm`。

## 日常工作流

```sh
chezmoi git pull -- --autostash --rebase
cd "$(chezmoi source-path)"
./tests/check-source.sh
chezmoi status --skip-secrets --exclude=encrypted
chezmoi diff --skip-secrets --exclude=encrypted <sanitized-target>
chezmoi apply <reviewed-target>
```

应用发生变化的 Telegram 模板或发起 Pi 模型请求前，需要先解锁 `rbw`。
通过 `rbw-agent` 使用 SSH identity 前也需要解锁。只有在可信终端中才能
查看完整的秘密渲染 diff。

新增配置时应指定单个文件：

```sh
chezmoi add ~/.config/example/config
```

禁止递归添加 `$HOME`、`.config` 或 XDG 根目录。可变状态和秘密应加入
`.chezmoiignore`，或交由合适的外部秘密后端管理。

## 详细文档

- [桌面配置所有权与依赖](docs/desktop.md)
- [可恢复的递归删除](docs/deletion-safety.md)
- [Pi 配置与凭据](docs/pi.md)
- [SSH identity 与 rbw-agent](docs/ssh.md)
- [编码代理操作规范](AGENTS.md)

在源码仓库根目录可通过以下脚本备份或恢复 age identity：

```sh
./scripts/backup-age-identity.sh
./scripts/restore-age-identity.sh
```
