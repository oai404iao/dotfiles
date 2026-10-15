# Dotfiles

[English](README.md) | [简体中文](README.zh-CN.md)

这是一个由 [chezmoi](https://www.chezmoi.io/) 管理的个人 Arch Linux
配置仓库。它支持 Bash 或 Zsh、图形化 Niri 设备、无图形设备、Neovim、Git
和 Pi，同时确保凭据与应用运行状态不会进入 Git。

## 主要特性

- 在 `chezmoi init` 时按机器能力选择配置。
- Bash 与 Zsh 共享公共登录环境，交互行为仍由各自单独管理。
- 共享登录环境导出 `DSH_HOME`，默认使用 `$XDG_DATA_HOME/dsh`
  （`~/.local/share/dsh`），并保留显式覆盖值。DSH 的所有内容仍放在这一
  单一根目录下，不纳入配置管理；现有 `~/.dsh` 数据不会自动迁移。
  如需覆盖，请在启动环境中设置，不要写入 DSH 的 `.env` 文件。
- 登录、桌面与用户服务环境默认使用 `LANG=zh_CN.UTF-8` 和
  `LANGUAGE=zh_CN:zh`，不持久设置 `LC_ALL`；交互式 Shell 使用完整的英文 locale。
  在 Niri 中，`gui app /absolute/path` 以桌面环境异步启动程序，不继承 Shell
  的 locale 或工作目录。[Locale 与启动说明](docs/desktop.md#locale-split)。
- 图形设备上的 XDG 目录更新服务独立使用英文环境，不改变桌面语言。
  [目录策略与迁移说明](docs/desktop.md#xdg-user-directories)。
- 比例界面使用 Adwaita Sans，终端使用 JetBrainsMono Nerd Font Mono，
  状态栏使用其 Nerd Font Propo 变体以对齐图标；Noto 字体提供 CJK、符号与
  Emoji 回退。
- Niri 使用模块化配置和可选择的显示器配置档案。
- Niri 桌面可在 init 时选择完整的 `dms` 或现有 `custom` 组件组合。
  [方案切换与所有权说明](docs/desktop-shells.md)涵盖 GUI 偏好的保留和两套启动流程的隔离。
- DMS 的 `lyrics`、`dankTodo` 插件、原生媒体界面补丁与 `dms-with-lyrics`
  启动器统一在 [oai404iao/dms-plugins](https://github.com/oai404iao/dms-plugins)
  维护，不再由 chezmoi 管理。[新设备设置](docs/desktop-shells.md#bilingual-lyrics)
  需要在启动 DMS 会话前检出经审阅的版本、运行离线测试并显式安装；
  chezmoi 不会自动获取或安装它们，apply 仅提醒依赖和补丁准备事项。
  双语歌词界面补丁支持 DMS 1.6.2/1.6.3；升级 DMS 后需从对应版本的
  原始源码树重新准备。插件数据只保留在本机。
- 可选的 [Tether 蓝牙 iPhone 通知](docs/tether.md)整合到 DMS，默认不开放 Wi-Fi
  或剪贴板访问；显式设置 `tetherMode="wifi-clipboard"` 可启用局域网与剪贴板同步。
  两种模式都禁用消息/联系人持久化，并设置不写入通知历史的规则。
  配对状态只留在本机。
- Niri 设备上的 GNOME Keyring D-Bus 激活统一使用软件包提供的 systemd
  用户服务；[密钥环数据及备份只留在本机](docs/desktop.md#desktop-keyring)。
- 为 Matugen 与 Waypaper 提供初始状态，同时避免后续 apply 覆盖应用生成值。
  DMS 也会生成 btop 与 fastfetch 的主题，并通过固定版本的 base46 插件接入 Neovim，
  无需启用旧 custom 桌面的整套模板。
- Satty、btop、Fcitx5 候选框、swaylock-effects 与 GTK 文件管理共享桌面风格，
  同时保留输入方案和应用状态。
- Nautilus 右键“脚本”子菜单支持复制绝对路径或相对于当前目录的路径。
  [使用方式与依赖](docs/desktop.md#nautilus-copy-path-scripts)。
- LazyVim 配置包含根据经过验证的本地插件检出重建的锁文件。
- Pi 在图形机器使用 Kitty 本地通知，无桌面机器使用 Telegram。模型及无桌面
  Telegram 凭据通过 `rbw` 从 Bitwarden 获取，参见
  [通知配置档案](docs/pi.md#notifications-by-machine-profile)。
  modifier 在 Pi 的 `npm/pnpm-workspace.yaml` 中管理三个精确版本的构建授权；
  其余 npm 安装状态仍保持忽略。
- Pi codemode 与直接工具调用并存（`on`，非 `only`）；参见
  [兼容性与子代理限制](docs/pi.md#codemode)。
- Pi 固定使用 Codex tools 5.0.0 和 subagent 1.2.0。Subagent 使用七个异步
  明文工具，全树并发上限为 4，邮箱默认等待 120 秒；参见
  [迁移说明](docs/pi.md#subagent-100-migration)。
- [Agent 派工说明](docs/pi.md#agent-delegation-guidance) 要求明确任务范围：
  scout/reviewer 负责只读检查，worker 使用继承的工具策略执行子任务，
  并报告改动、实际验证和未完成项。
- [全局 Pi 指令](docs/pi.md#global-agent-instructions) 在
  `my_skills/prompts/pi-global-agents.md` 维护，chezmoi 从 `main` 获取，
  缓存周期为 24 小时；临时文件按任务存放于
  `~/.local/state/agents/tmp/`，用后保留，避免使用 `/tmp`。
- [全局 skills](docs/skills.md) 通过清单和手动 `pnpm dlx skills` 脚本安装；
  `~/.agents/skills/` 下的下载内容不纳入本仓库。
- OpenSSH 使用经 age 加密的公钥选择器与主机元数据，客户端私钥由
  Bitwarden 中的 `rbw-agent` 使用；Git 身份元数据同样经过加密。

## 仓库结构

```text
.
├── .chezmoi.toml.tmpl       # 本机数据与秘密后端
├── .chezmoiignore           # 条件化目标和状态排除规则
├── dot_config/
│   ├── shell/, bash/, zsh/  # Shell 环境与交互模块
│   ├── git/, nvim/          # 加密 Git 身份与 LazyVim
│   ├── environment.d/       # locale、图形输入法与 rbw-agent socket
│   ├── fontconfig/, gtk-*/  # 用户字体别名与 GTK 默认值
│   ├── niri/, waybar/       # Niri 桌面会话
│   ├── kitty/, fuzzel/      # 终端与启动器
│   ├── mako/, matugen/      # 通知与生成的主题配色
│   ├── waypaper/            # 壁纸集成
│   └── private_pi/agent/    # 使用私有权限的 Pi 声明式配置
├── private_dot_ssh/         # 通用 SSH 策略与加密清单
├── dot_local/bin/           # 用户命令
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
  历史、数据库、会话、Pi 登录/信任状态、下载的软件包，以及桌面密钥环数据库和备份。

即使远端仓库是私有的，也要把本仓库视为公开仓库。禁止加入凭据、递归导入
`$HOME` 或 XDG 根目录，也不要提交恢复备份。

受管 Pi 模型 provider 不保存 API 凭据。
`dot_config/private_pi/agent/modify_private_auth.json` 将 `rbw` API key
命令引用合并到权限为 `0600` 的私有 `auth.json`：

```json
{
  "deepseek": {
    "type": "api_key",
    "key": "!rbw get 'pi spiredive api key'"
  }
}
```

Pi 每个进程只解析一次该命令，并将结果保存在内存中。
`deepseek`、`openai` 和 `xai` 使用上面的 Spiredive 引用；`anthropic`
使用 `!rbw get 'pi krill api key'`。modifier 仅替换受管 API key 条目的
`type`/`key`，保留额外字段以及其他所有 provider 和值。受管 provider 的
OAuth/非 API key 冲突，以及格式错误、键重复或非对象 JSON 都会导致失败，
不输出替换内容，也不覆盖目标。应用引用不会访问 `rbw` 或 vault。
Git 只跟踪 modifier 源码：绝不要执行 `chezmoi add auth.json` 或提交其渲染数据。
即使使用 `--skip-secrets` 也绝不要 diff `auth.json`，因为保留的条目可能包含
key 或 OAuth token。

Telegram 扩展自身不支持解析命令，因此 chezmoi 会将 Bitwarden 中的值渲染到
权限为 `0600` 的目标文件。不要显示未过滤的 Pi diff。`--skip-secrets`
只会跳过秘密模板，不会遮盖目标文件里已经存在的明文凭据，也不会排除原生
加密源码。广泛预览时应同时使用 `--exclude=encrypted`。

## 机器配置档案

`.chezmoi.toml.tmpl` 会在本机 chezmoi 配置中初始化以下非秘密数据：

| 键 | 可选值 | 作用 |
|---|---|---|
| `role` | `desktop`、`laptop`、`server` | 机器角色元数据 |
| `shell` | `zsh`、`bash` | 记录 Shell 偏好；两套配置均部署，不修改登录 Shell |
| `graphical` | 布尔值 | 启用图形应用配置 |
| `niri` | 布尔值 | 启用 Niri 及桌面会话所有权管理 |
| `desktopShell` | `custom`、`dms` | 选择 Niri 桌面方案；未设置时保留 `custom` |
| `tether` | 布尔值，默认 `false` | 仅在图形化 Niri/DMS 设备启用蓝牙 iPhone 通知配置；安装及服务启用仍需手动完成 |
| `niriOutputProfile` | `auto`、命名档案 | 选择渲染后的显示器配置 |
| `work` | 布尔值 | 工作设备元数据 |
| `sshAgent` | 布尔值 | 启用 rbw SSH 客户端和公钥选择器 |
| `sshInboundIdentity` | `none`、`private`、`uni` | 选择 `authorized_keys` 所有权 |

显示器硬件未知时请选择 `niriOutputProfile = "auto"`。机器数据中禁止存放凭据。

## 前置依赖

在 Arch Linux 上安装仓库级工具：

```sh
sudo pacman -S --needed git chezmoi age rbw openssh python bash zsh
```

完整源码验证需要 Bash 和 Zsh；实际运行时只需要所选的 Shell。还需确保已安装
`neovim` 和 `less`。Pi 与 Node.js 需要单独安装。图形环境依赖见
[docs/desktop.md](docs/desktop.md)；本仓库不提供系统级软件包引导安装。

按全部配置档分类并附用途注释的 Arch 软件包清单见
[pacman 包](docs/packages/pacman.txt)和 [AUR 包](docs/packages/aur.txt)。
按实际启用的配置档选择；它们是仅保留在源码仓库的清单，并非安装脚本或本机全部
已安装软件的导出。pacman 清单把 `archlinuxcn` 第三方二进制包与官方包分开标注；
`noto-fonts-lite` 等 AUR 提供者可能与官方替代包冲突。

宿主机必须已经生成 `en_US.UTF-8` 与 `zh_CN.UTF-8`。图形字体配置还需要
Fontconfig，以及 Adwaita、Noto、Noto CJK、Noto Symbols、Noto Color Emoji
和 JetBrains Mono Nerd Font 字体族；对应的 Arch 软件包见
[docs/desktop.md](docs/desktop.md)。

### Zsh 框架与主题

Oh My Zsh、Powerlevel10k、zsh-autosuggestions 和 zsh-syntax-highlighting
通过 `.chezmoiexternal.toml` 中固定 commit 的归档外部依赖管理。Chezmoi
同时管理其版本以及 Zsh、P10k 配置；下载的源码、Git 元数据和运行时缓存
不提交到本仓库。OMZ 自动更新已禁用。升级需要显式修改锁定 URL、测试并
定向应用已审阅的目标，而不是运行 `omz update` 或 `git pull`。
两套 Shell 配置及这些依赖均不受 `shell` 偏好影响。

接管已有安装前必须备份。非精确归档保留本机额外文件，OMZ 归档排除
`custom/`、缓存和日志内容。定向迁移、离线检查以及上游废弃文件的处理方法见
[Zsh 迁移与升级](docs/zsh.md)。

### 用户级 Node.js

单独安装 pnpm 12（例如 AUR 的 `pnpm-bin`），然后加载共享 Shell 环境，
无需 `sudo` 即可安装用户级运行时：

```sh
. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/toolchains.sh"
pnpm runtime set node 24 -g
pnpm add -g npm@12.1.0
```

pnpm 本体仍由系统包管理器维护；Node.js 和 npm/npx 位于 `PNPM_HOME`
（默认 `~/.local/share/pnpm`）下。Chezmoi 只管理环境配置，不管理下载的
运行时或全局包。

Bash 和 zsh 配置均纳入管理，不受 `shell` 偏好影响。定向 apply 前，
备份已有的 `~/.bash_profile`、`~/.bashrc`、`~/.zshenv`、
`~/.config/bash` 和 `~/.config/zsh`。将废弃的 `~/.zshrc` 移入备份；
zsh 现在读取 `~/.config/zsh/.zshrc`。

从 nvm 迁移时，还应备份 `~/.config` 下的 `shell/toolchains.sh`、
`shell/nvm.sh` 和 `bash/rc.d/50-node.bash` / `zsh/rc.d/50-node.zsh`。
`.chezmoiremove` 会移除 nvm 加载脚本；新 Shell 会清除继承的 nvm 运行时
PATH 和变量。Chezmoi 不会卸载 nvm 或其中的全局包：先迁移仍需使用的工具，
再单独卸载系统 nvm 包，并将其用户运行时目录移至回收站。
应用后打开新终端，用 `command -v node npm npx pnpm` 检查：Node/npm/npx
应指向 `$PNPM_HOME/bin`，pnpm 应指向系统包。

### sudo 图形密码弹窗

图形配置部署基于 Zenity 的密码助手 `~/.local/bin/sudo-askpass`。
共享登录环境在助手可执行时导出 `SUDO_ASKPASS`，保留已有的非空自定义值。
命令行脚本或 Pi 使用 `sudo -A 命令`；不会替换普通 `sudo`，也不会修改
sudoers、启用免密码或提供逐条命令审批。
依赖、定向应用和生效方式见[配置说明](docs/desktop.md#graphical-sudo-prompts)。

## 在新机器上初始化

### 1. 只初始化，不立即应用

先配置 GitHub SSH 访问，然后执行：

```sh
chezmoi init git@github.com:oai404iao/dotfiles.git
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
- `pi krill api key`
- `pi telegram bot token`（仅无桌面机器）
- `pi telegram chat id`（仅无桌面机器）

SSH 客户端机器还需要 [docs/ssh.md](docs/ssh.md) 所描述的原生 Bitwarden
SSH key 集合。使用 rbw 默认的 1 小时空闲锁定超时。已显式配置超时的机器可通过
以下命令恢复默认值：

```sh
rbw config unset lock_timeout
```

### 3. 准备应用的外部依赖

根据机器用途安装对应的 Shell、桌面、Neovim 和 Pi 依赖。锁定的 Pi 扩展要求
Pi 1.2.0 或更高版本、Node.js 22.19 或更高版本。图形机器还需要将
`~/.local/share/pi/extensions/pi-local-notify` 软链接到可信的本地插件源码，
参见[本地插件配置](docs/pi.md#notifications-by-machine-profile)。
无桌面机器不需要本地扩展 checkout。
升级 Pi 主程序后需完全退出并重启；`/reload` 不能更新运行中的 SDK。
若 `spawn_agent` 报 `createCodemodeExtension` 缺失，参见
[子代理启动排障](docs/pi.md#createcodemodeextension-is-not-a-function)。

### 4. 验证源码

```sh
CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
```

测试套件应保持离线。Pi 模板测试使用假的 `rbw`；安装了 `niri` 时，其配置会
渲染到隔离的临时 HOME 并接受验证。SSH 配置档案与公钥选择器使用生成的假
数据测试；显式可信检查还会验证真实 age 密文，但不会输出解密内容或访问
vault。

### 5. 审阅并应用

对于没有既有 Pi 明文凭据配置的新机器：

```sh
chezmoi status --skip-secrets --exclude=encrypted
chezmoi diff --skip-secrets --exclude=encrypted
chezmoi apply --interactive --skip-secrets --exclude=encrypted

CHECK_PRIVATE_CONFIG=1 ./tests/check-source.sh
chezmoi apply "$HOME/.gitconfig" "$HOME/.config/git"
chezmoi apply "$HOME/.ssh"
```

第一次 apply 会排除秘密模板。仅无桌面机器需要运行以下定向命令，渲染私有
Telegram 配置且不显示秘密 diff：

```sh
rbw unlock
chezmoi apply \
  "$HOME/.config/pi/agent/extensions/pi-telegram-notify/config.json"
```

上面的其余命令会单独验证并应用 age 加密的 Git
与 SSH 元数据；如果机器的两项 SSH 能力均关闭，则省略 SSH apply。

auth modifier 会安装全部四个模型凭据引用，无需 `/login`。接管或更新既有
`auth.json` 前，先退出所有使用该目录的 Pi 进程，避免并发写入认证文件，
再将文件私密备份到源码和保留的 agent 临时目录
（`~/.local/state/agents/tmp/`）之外，目录权限为 `0700`、文件权限为 `0600`。
审阅 modifier 源码而非 auth diff，然后仅应用：

```sh
chezmoi apply --exclude=scripts,encrypted ~/.config/pi/agent/auth.json
```

之后重启 Pi。受管 provider 若存在冲突的 OAuth/非 API key 凭据，
必须由用户明确移除后才能重试，绝不会自动转换。应用该目标无需解锁 `rbw`。
在每个新 Pi 进程解析完该命令前保持 `rbw` 已解锁。结果会缓存在该进程内，
所以之后锁定 `rbw` 不会中断它。生命周期和恢复细节见
[docs/pi.md](docs/pi.md)。

如果机器已经存在配置，应先备份，然后逐个组件接管：

```sh
chezmoi status --skip-secrets <target>
chezmoi diff --skip-secrets <sanitized-target>
chezmoi apply <reviewed-target>
```

即使迁移后，也绝不要 diff Pi `auth.json`；保留的凭据仍属于本机状态。
不要 diff 可能包含明文密钥的既有 Pi `models.json`。请按照
[docs/pi.md](docs/pi.md#credentials) 中的定向 auth 应用及直接脱敏流程处理。
不要 diff 加密的 SSH 目标，否则会输出解密后的主机清单；请使用
[docs/ssh.md](docs/ssh.md)
中的可信检查与定向 apply。

应用完成后启动新的登录会话，并检查：

```sh
locale
fc-match sans-serif
fc-match monospace
chezmoi status --skip-secrets --exclude=encrypted
```

## 日常工作流

```sh
chezmoi git pull -- --autostash --rebase
cd "$(chezmoi source-path)"
./tests/check-source.sh
chezmoi status --skip-secrets --exclude=encrypted
chezmoi diff --skip-secrets --exclude=encrypted <sanitized-target>
chezmoi apply <reviewed-target>
```

应用发生变化的 Telegram 模板、新 Pi 进程首次解析模型 key，以及通过
`rbw-agent` 使用 SSH identity 前，需要先解锁 `rbw`。已经初始化的 Pi
进程会继续在内存中保留解析后的 key。绝不要显示 auth 或 Telegram 的
秘密 diff；仅预览明确指定且已脱敏的目标。

新增配置时应指定单个文件：

```sh
chezmoi add ~/.config/example/config
```

禁止递归添加 `$HOME`、`.config` 或 XDG 根目录。可变状态和秘密应加入
`.chezmoiignore`，或交由合适的外部秘密后端管理。

## 详细文档

- [桌面配置所有权与依赖](docs/desktop.md)
- [DMS/custom 桌面方案与切换](docs/desktop-shells.md)
- [可选的 Tether 蓝牙 iPhone 通知](docs/tether.md)
- [Pi 配置与凭据](docs/pi.md)
- [SSH identity 与 rbw-agent](docs/ssh.md)
- [公开仓库安全流程](docs/publication.md)
- [编码代理操作规范](AGENTS.md)

在源码仓库根目录可通过以下脚本备份或恢复 age identity：

```sh
./scripts/backup-age-identity.sh
./scripts/restore-age-identity.sh
```
