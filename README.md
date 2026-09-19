# KBManager.Build

> KBManager 的构建工具仓库：**在 WSL 里编译，把 Windows 产物送到 C 盘，直接在 Windows 上测 GUI。**

[kbmanager]: https://github.com/hjl-qwq/KBManager

本仓库不包含业务代码，只负责把 [KBManager][kbmanager] 源码变成能在 Windows 上双击运行的 `.exe`：

```
WSL（Linux）                                         Windows
────────────────────────────────────────────         ──────────────────────────────
KBManager/*.cs
    │  dotnet publish -r win-x64
    ▼
KBManager.Build/artifacts/win-x64/
    ├── gui/  KBManager.GUI.exe + 依赖 + 原生库
    └── cli/  KBManager.CLI.exe + 依赖 + 原生库
    │  cp -r  （deploy）
    ▼
/mnt/c/Users/<用户>/KBManager-win/{gui,cli}  ───────►  KBManager.GUI.exe
```

---

## 为什么单独做一个仓库

- **构建逻辑和源码解耦**：构建方式可以独立迭代、单独打 tag，不污染 KBManager 的提交历史。
- **交叉编译，不在 WSL 里跑 GUI**：.NET 支持从 Linux 直接产出 Windows x64 产物，得到的是真正的 `.exe`，不需要 Wine 或 WSLg。
- **在 Windows 上测才接近真实用户**：字体、DPI、文件对话框、`%APPDATA%` 行为、原生库加载，在 Windows 上跑一遍才算数。
- **一条命令就能验证**：`./build.sh run` = 编译 + 发布 + 复制 + 启动。

## 环境要求

| 项 | 要求 | 说明 |
| --- | --- | --- |
| 系统 | WSL2 / 任意 Linux | 脚本为 bash，需要 bash 4.4+ |
| .NET SDK | 8.0 | `./setup-wsl.sh` 一键用户级安装，不需要 sudo |
| 磁盘 | 约 1 GB | SDK 约 200 MB + NuGet 缓存 + 产物 |
| Windows 运行时 | .NET 8 运行时（`Microsoft.NETCore.App 8.x`） | 用 `--self-contained` 发布时不需要 |
| 可选工具 | `zip` 或 `python3`（`--zip`）、`shellcheck`（本地 lint） | 缺失时对应功能会降级并提示 |

## 目录结构

```
KBManager.Build/
├── build.sh                     # 唯一入口，所有命令都从这里进
├── setup-wsl.sh                 # 安装 .NET SDK（用户级，~/.dotnet）
├── lib/
│   ├── common.sh                # 日志、配置、SDK/仓库/Windows 路径探测
│   ├── cmd_build.sh             # restore / build
│   ├── cmd_test.sh              # test
│   ├── cmd_publish.sh           # publish（交叉编译）
│   ├── cmd_deploy.sh            # deploy（复制到 C 盘）
│   ├── cmd_run.sh               # run / run-local
│   ├── cmd_doctor.sh            # doctor（环境自检）
│   └── cmd_clean.sh             # clean
├── config/build.env.example     # 本地配置示例（复制成 config/build.env）
└── .github/workflows/shellcheck.yml
```

## 快速开始

```bash
# 两个仓库放在同一级目录下（这是默认的查找方式，不必配任何变量）
#   ~/KBManager_solution/KBManager
#   ~/KBManager_solution/KBManager.Build

cd ~/KBManager_solution/KBManager.Build

./setup-wsl.sh          # 仅第一次：安装 .NET 8 SDK 到 ~/.dotnet
./build.sh doctor       # 自检：SDK、源码位置、Windows 路径、运行时
./build.sh run          # 编译 → 发布 Windows 产物 → 复制到 C 盘 → 启动 GUI
```

`run` 结束后，Windows 上出现 KBManager 窗口即为链路通畅。之后改完代码再敲一次 `./build.sh run` 即可。

如果源码不在同级目录：

```bash
./build.sh run --source ~/work/KBManager
# 或者写进本地配置（不会提交到 git）
echo 'KB_SOURCE="$HOME/work/KBManager"' >> build.env
```

## 命令

| 命令 | 作用 |
| --- | --- |
| `doctor` | 打印整条链路的环境信息，出问题时先跑这个 |
| `build` | 在当前平台（WSL/Linux）编译 core + CLI + GUI |
| `restore` | 只做 NuGet 还原 |
| `test` | 运行 `KBManager.Tests` 的 xUnit 测试 |
| `publish` | 交叉编译 Windows 产物到 `artifacts/<rid>/{gui,cli}` |
| `deploy` | `publish` + 复制到 Windows 可见目录 |
| `run` | `deploy` + 在 Windows 上启动 GUI（最短验证路径） |
| `run-local` | 发布 `linux-x64` 并用 WSLg 在本机跑 GUI（不经过 Windows） |
| `release` | `test` + `deploy`，提交前跑这个 |
| `clean` | 清理编译输出与 `artifacts/`（`--deep` 连 `bin/obj` 一起删） |

## 选项

| 选项 | 说明 |
| --- | --- |
| `-C, --source DIR` | 指定 KBManager 源码仓库位置 |
| `-c, --config NAME` | 构建配置 `Debug` / `Release`（默认 `Release`） |
| `--rid RID` | 目标运行时（默认 `win-x64`，可换 `win-arm64` / `linux-x64`） |
| `-o, --out DIR` | 产物根目录（默认 `<本仓库>/artifacts`） |
| `--deploy-dir DIR` | 部署落地目录，WSL 路径写法（默认 `C:\Users\<用户>\KBManager-win`） |
| `-s, --self-contained` | 自包含发布，目标机不需要 .NET |
| `--framework-dependent` | 框架依赖发布（默认） |
| `--gui` / `--cli` | 只处理指定目标（默认两者都处理） |
| `--zip` | 额外产出 `artifacts/KBManager-<rid>-<config>-<commit>.zip` |
| `--with-tests` | `build` 时把测试项目一起编译 |
| `--no-restore` | 给 dotnet 传 `--no-restore` |
| `--no-publish` | `deploy` / `run` 跳过发布，直接用现有产物 |
| `--run` | `deploy` 完成后启动 GUI |
| `--deep` | `clean` 时删除源码仓库里的 `bin/`、`obj/` |
| `-v, --verbose` | 回显实际执行的 dotnet 命令 |
| `-n, --dry-run` | 只打印会做什么，不真正执行 |
| `--` | 后面的参数原样透传给 `dotnet` |

示例：

```bash
./build.sh doctor
./build.sh build --with-tests
./build.sh run                                  # 最常用
CONFIG=Debug ./build.sh run                     # Debug 配置（带 Avalonia 诊断）
./build.sh deploy --self-contained --zip        # 目标机没装 .NET 时
./build.sh deploy --deploy-dir /mnt/d/KBManager-win
./build.sh run-local                            # 用 WSLg 在 Linux 侧看界面
./build.sh clean --deep
./build.sh publish -n                           # 先看会执行什么
```

## 配置

优先级：**命令行参数 > 环境变量 > `build.env` > 内置默认值**。

`build.env` 可以放在仓库根目录，也可以放在 `config/build.env`，该文件已被 `.gitignore` 忽略。
完整字段见 [`config/build.env.example`](config/build.env.example)。

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `KB_SOURCE` | 自动查找 | KBManager 源码仓库路径 |
| `CONFIG` | `Release` | 构建配置 |
| `RID` | `win-x64` | 目标运行时 |
| `SELF_CONTAINED` | `0` | `1` = 自包含发布 |
| `ARTIFACTS` | `<仓库>/artifacts` | 产物根目录 |
| `WIN_DEPLOY_DIR` | `C:\Users\<用户>\KBManager-win` | 部署落地目录（WSL 路径写法） |
| `DOTNET_BIN` | 自动查找 | 指定 dotnet 可执行文件 |
| `NUGET_PACKAGES` | `~/.nuget/packages` | NuGet 包缓存目录 |
| `KB_WINDOWS_USER` | 当前 Linux 用户名 | 找不到 Windows 用户目录时手动指定 |
| `KB_WIN_MOUNT` | `/mnt/c` | Windows 挂载点 |

`KBM_BUILD_ROOT` 在 `build.env` 里可用，指向本仓库根目录。

## 产物

发布后的 `artifacts/<rid>/`：

```
artifacts/win-x64/
├── gui/
│   ├── KBManager.GUI.exe            # 入口
│   ├── KBManager.GUI.dll / KBManager.core.dll
│   ├── Avalonia*.dll / *.SkiaSharp 等托管依赖
│   ├── libSkiaSharp.dll / libHarfBuzzSharp.dll / av_libglesv2.dll   # Avalonia 渲染原生库
│   ├── git2-*.dll                   # LibGit2Sharp 原生库（Git 功能必需）
│   ├── e_sqlite3.dll                # SQLite 原生库（索引库）
│   └── build-info.txt               # 这批产物对应的提交与配置
├── cli/  （结构同上）
└── build-info.txt
```

`publish` 结束时会自动校验这些关键文件是否存在，缺少 `git2-*` 之类的原生库会直接报错，避免拿着不完整的产物去 Windows 上排查半天。

`build-info.txt` 记录提交号、分支、是否有未提交改动、构建配置、RID、SDK 版本，方便确认 Windows 上跑的是哪一次构建。

## 两种发布模式

| 模式 | 命令 | 体积 | 目标机要求 |
| --- | --- | --- | --- |
| 框架依赖（默认） | `./build.sh deploy` | 约 34 MB | 需要 .NET 8 运行时 |
| 自包含 | `./build.sh deploy -s` | 约 70–90 MB | 无 |

KBManager 的 GUI 基于 Avalonia，**不需要** Windows Desktop Runtime，只要有 `Microsoft.NETCore.App 8.x` 即可。
`./build.sh doctor` 会直接告诉你 Windows 上有没有这个运行时。

## 部署细节

- 只替换目标目录下的 `gui/`、`cli/` 两个子目录，不会动该目录里的其他内容。
- **保留 `theme.json`**：GUI 首次运行会在 exe 同目录生成 `theme.json` 并读取它，重复部署时该文件会被保留，不会被默认值覆盖。
- 若目标目录里的文件正被占用（GUI 还在运行），自动退化为 `gui-YYYYmmdd-HHMMSS/` 目录并给出提示，而不是让整次部署失败。
- 目标目录优先用 `--deploy-dir` / `WIN_DEPLOY_DIR`；否则在 `/mnt/c/Users/*` 里按 `NTUSER.DAT` 找当前用户，落到 `KBManager-win`。
- `run` 通过 WSL interop 调用 `cmd.exe /c start` 启动 GUI，因此不需要手动去资源管理器里双击。

> 不建议直接在 `\\wsl$` 网络路径下双击 exe：IO 慢，且部分原生库在 UNC 路径下加载行为不稳定。请用 `deploy` / `run` 复制到 C 盘再运行。

## 在 Windows 上测试时可能要知道的

| 内容 | 位置 |
| --- | --- |
| 界面配色 | exe 同目录的 `theme.json`（首次运行自动生成，删除即恢复默认） |
| 应用配置 | `%APPDATA%\KBManager\config.json`（不随部署目录变化） |
| 知识库索引 | `<知识库目录>\.kbdatabase\KbInfo.db` |
| 崩溃日志 | Windows 桌面 `KBManager_crash.log` |

## CI

`.github/workflows/shellcheck.yml` 会在 push / PR 时：

1. 对所有脚本做 `bash -n` 语法检查；
2. 跑 `shellcheck -x`；
3. 做一次冒烟测试（`--help`、`--version`、`doctor`）。

工作流不依赖 KBManager 源码，也不下载 SDK，因此几秒钟就能跑完。

## 常见问题

**`找不到 KBManager 源码仓库`**
用 `--source /path/to/KBManager` 指定，或写进 `build.env`。该目录必须包含 `KBManager.core/`、`KBManager.CLI/`、`KBManager.GUI/`。

**`未找到可用的 .NET SDK`**
先跑 `./setup-wsl.sh`。`build.sh` 会按 `PATH` → `$DOTNET_ROOT` → `~/.dotnet` → 仓库内 `.dotnet/` 的顺序查找，`doctor` 会显示实际用的是哪一个。

**首次编译很慢**
第一次要还原 Avalonia、EF Core、LibGit2Sharp 等包，属正常现象；之后有缓存会快很多。清理：`./build.sh clean --deep`。

**Windows 上双击 exe 提示缺少运行时**
用 `./build.sh deploy --self-contained`，或在 Windows 上装 .NET 8 运行时。`doctor` 会列出 Windows 侧已有的运行时。

**改了代码但 Windows 上界面没变**
`deploy` 默认会重新 `publish`；如果用了 `--no-publish`，拿到的是旧产物。另外注意 GUI 可能还在运行（旧进程占用文件时会自动部署到时间戳目录）。产物对应哪次提交可以看 `build-info.txt`。

**`dotnet publish` 报 `NETSDK1047` / 找不到 RID 资源**
通常是加了 `--no-restore` 但换了 `--rid`。去掉 `--no-restore` 重新发布即可。

**WSLg 下 `run-local` 没有窗口**
确认 `echo $DISPLAY` 有值、Windows 11 / 已启用 WSLg；也可以直接用默认的 `run`，让 GUI 跑在 Windows 上。

---

## 与 KBManager 仓库内 `scripts/` 的关系

KBManager 仓库里曾放过一版原型脚本（`scripts/build.sh`、`scripts/setup-wsl.sh`）。本仓库是它的整理版：命令拆到 `lib/`、增加了源码自动定位、产物校验、`build-info.txt`、`--zip`、`--dry-run`、`run-local`、`theme.json` 保留和 CI，功能已完全覆盖原型脚本。
