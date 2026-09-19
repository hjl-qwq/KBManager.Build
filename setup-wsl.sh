#!/usr/bin/env bash
#
# 在 WSL / Linux 上安装编译 KBManager 所需的 .NET SDK。
#
# 特点：用户级安装（不需要 sudo），所有文件只写进一个目录，卸载 = 删除该目录。
#
#   ./setup-wsl.sh                             # 安装 .NET 8 SDK 到 ~/.dotnet
#   DOTNET_CHANNEL=9.0 ./setup-wsl.sh          # 换 SDK 大版本
#   DOTNET_INSTALL_DIR="$PWD/.dotnet" ./setup-wsl.sh   # 装到本仓库内部
#
# build.sh 会自动发现这些位置，因此不配置 PATH 也能直接使用。
#
set -euo pipefail

KBM_BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

CHANNEL="${DOTNET_CHANNEL:-8.0}"
INSTALL_DIR="${DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
DOWNLOAD_URL="https://dot.net/v1/dotnet-install.sh"

log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[32m  +\033[0m %s\n' "$*"; }
die()  { printf '\033[31m  x\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1) 已经有可用的 SDK 就不重复安装
# ---------------------------------------------------------------------------
find_existing_dotnet() {
    if command -v dotnet >/dev/null 2>&1; then command -v dotnet; return 0; fi
    if [[ -x "$HOME/.dotnet/dotnet" ]]; then printf '%s\n' "$HOME/.dotnet/dotnet"; return 0; fi
    if [[ -x "$INSTALL_DIR/dotnet" ]]; then printf '%s\n' "$INSTALL_DIR/dotnet"; return 0; fi
    return 1
}

if existing="$(find_existing_dotnet)"; then
    if "$existing" --list-sdks 2>/dev/null | grep -q '^[0-9]'; then
        log "已检测到可用的 .NET SDK，无需安装：$existing"
        "$existing" --list-sdks | sed 's/^/  /'
        exit 0
    fi
    warn "检测到 $existing，但没有可用的 SDK，继续安装。"
fi

# ---------------------------------------------------------------------------
# 2) 取官方安装脚本
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
INSTALLER="$TMP_DIR/dotnet-install.sh"

log "下载官方安装脚本：$DOWNLOAD_URL"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$DOWNLOAD_URL" -o "$INSTALLER"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALLER" "$DOWNLOAD_URL"
else
    die "需要 curl 或 wget，请先安装其中之一。"
fi

# ---------------------------------------------------------------------------
# 3) 安装
# ---------------------------------------------------------------------------
log "安装 .NET SDK（channel $CHANNEL）到 $INSTALL_DIR —— 首次约 200MB，请耐心等待"
bash "$INSTALLER" --channel "$CHANNEL" --install-dir "$INSTALL_DIR" --no-path

DOTNET_BIN="$INSTALL_DIR/dotnet"
[[ -x "$DOTNET_BIN" ]] || die "安装似乎失败了：找不到 $DOTNET_BIN"

ok "安装完成，当前 SDK："
"$DOTNET_BIN" --list-sdks | sed 's/^/  /'

cat <<EOF

下一步
------
build.sh 会自动发现 $DOTNET_BIN，不改 PATH 也能直接用：

  cd $KBM_BUILD_ROOT
  ./build.sh doctor        # 环境自检
  ./build.sh deploy        # 编译 + 发布 Windows 产物 + 复制到 C 盘
  ./build.sh run           # 上一条 + 在 Windows 上启动 GUI

如果还想在任意目录直接敲 dotnet 命令，把下面两行加入 ~/.bashrc：

  export DOTNET_ROOT="$INSTALL_DIR"
  export PATH="\$DOTNET_ROOT:\$PATH"

然后 source ~/.bashrc 生效。
EOF
