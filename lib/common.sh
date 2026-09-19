# shellcheck shell=bash
#
# KBManager.Build —— 公共函数库
#
# 由 build.sh source，不单独执行。提供：
#   * 彩色日志与命令执行封装
#   * 配置加载（默认值 < build.env < 环境变量 < 命令行）
#   * .NET SDK / 源码仓库 / Windows 目录探测
#   * 产物校验、构建信息、打包等复用逻辑
#
# 约定：内部全局变量统一使用 KBM_ 前缀。

[[ -n "${KBM_COMMON_LOADED:-}" ]] && return 0
KBM_COMMON_LOADED=1

# ---------------------------------------------------------------------------
# 颜色与日志
# ---------------------------------------------------------------------------
if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    KBM_C_RESET=$'\033[0m'
    KBM_C_CYAN=$'\033[36m'
    KBM_C_GREEN=$'\033[32m'
    KBM_C_YELLOW=$'\033[33m'
    KBM_C_RED=$'\033[31m'
    KBM_C_DIM=$'\033[2m'
else
    KBM_C_RESET=""
    KBM_C_CYAN=""
    KBM_C_GREEN=""
    KBM_C_YELLOW=""
    KBM_C_RED=""
    KBM_C_DIM=""
fi

# 消息统一输出到 stderr：stdout 只留给查询类命令的返回值
log()  { printf '%s==>%s %s\n' "$KBM_C_CYAN" "$KBM_C_RESET" "$*" >&2; }
ok()   { printf '%s  +%s %s\n' "$KBM_C_GREEN" "$KBM_C_RESET" "$*" >&2; }
warn() { printf '%s  !%s %s\n' "$KBM_C_YELLOW" "$KBM_C_RESET" "$*" >&2; }
err()  { printf '%s  x%s %s\n' "$KBM_C_RED" "$KBM_C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# 命令执行封装（支持 --verbose / --dry-run）
# ---------------------------------------------------------------------------
kbm_shell_quote() {
    local out="" arg
    for arg in "$@"; do
        printf -v arg '%q' "$arg"
        out+="$arg "
    done
    printf '%s' "${out% }"
}

# run <cmd> [args...]：verbose 时回显命令，dry-run 时只回显不执行
run() {
    if [[ "${KBM_DRY_RUN:-0}" == "1" ]]; then
        printf '%s  [dry-run]%s %s\n' "$KBM_C_YELLOW" "$KBM_C_RESET" "$(kbm_shell_quote "$@")" >&2
        return 0
    fi
    if [[ "${KBM_VERBOSE:-0}" == "1" ]]; then
        printf '%s  $ %s%s\n' "$KBM_C_DIM" "$(kbm_shell_quote "$@")" "$KBM_C_RESET" >&2
    fi
    "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# 配置加载
#
# 优先级：命令行参数 > 环境变量 > build.env > 内置默认值
# 环境变量在 source 配置文件之前先记录下来，之后原样恢复，从而压过文件内容。
# ---------------------------------------------------------------------------
kbm_load_config() {
    local -a env_pairs=()
    local var
    for var in KB_SOURCE CONFIG RID SELF_CONTAINED ARTIFACTS WIN_DEPLOY_DIR \
               DOTNET_BIN NUGET_PACKAGES DOTNET_CLI_HOME; do
        if [[ -n "${!var-}" ]]; then
            env_pairs+=("$var=${!var}")
        fi
    done

    # 可选的本地配置（不纳入版本管理），后者优先。
    # KBM_CONFIG_FILE / KBM_DEPLOY_DIR 会被其他子命令文件读取，故 export。
    export KBM_CONFIG_FILE=""
    local f
    for f in "$KBM_BUILD_ROOT/build.env" "$KBM_BUILD_ROOT/config/build.env"; do
        if [[ -f "$f" ]]; then
            # shellcheck disable=SC1090
            source "$f"
            export KBM_CONFIG_FILE="$f"
            break
        fi
    done

    # 恢复调用方通过环境变量显式指定的值
    local pair
    for pair in ${env_pairs[@]+"${env_pairs[@]}"}; do
        # shellcheck disable=SC2163
        export "$pair"
    done

    # 默认值 → 内部变量
    KBM_SOURCE_DIR="${KB_SOURCE:-}"
    KBM_CONFIG="${CONFIG:-Release}"
    KBM_RID="${RID:-win-x64}"
    KBM_SELF_CONTAINED="${SELF_CONTAINED:-0}"
    KBM_ARTIFACTS="${ARTIFACTS:-$KBM_BUILD_ROOT/artifacts}"
    export KBM_DEPLOY_DIR="${WIN_DEPLOY_DIR:-}"
    KBM_NUGET_PACKAGES="${NUGET_PACKAGES:-}"
    KBM_DOTNET_BIN="${DOTNET_BIN:-}"

    # 与命令行为相关的开关（仅由命令行设置，这里给默认值）
    KBM_TARGETS=(${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"})
    [[ ${#KBM_TARGETS[@]} -gt 0 ]] || KBM_TARGETS=(gui cli)
    KBM_VERBOSE="${KBM_VERBOSE:-0}"
    KBM_DRY_RUN="${KBM_DRY_RUN:-0}"
    KBM_ZIP="${KBM_ZIP:-0}"
    KBM_DEEP="${KBM_DEEP:-0}"
    KBM_WITH_TESTS="${KBM_WITH_TESTS:-0}"
    KBM_NO_RESTORE="${KBM_NO_RESTORE:-0}"
    KBM_SKIP_PUBLISH="${KBM_SKIP_PUBLISH:-0}"
    KBM_RUN_AFTER_DEPLOY="${KBM_RUN_AFTER_DEPLOY:-0}"
    KBM_EXTRA_ARGS=(${KBM_EXTRA_ARGS[@]+"${KBM_EXTRA_ARGS[@]}"})

    export DOTNET_CLI_TELEMETRY_OPTOUT=1
    export DOTNET_NOLOGO=1
    if [[ -n "$KBM_NUGET_PACKAGES" ]]; then
        export NUGET_PACKAGES="$KBM_NUGET_PACKAGES"
    fi
}

# publish / deploy / run 只对可执行目标有意义，过滤掉 core / tests
kbm_keep_app_targets() {
    local -a kept=()
    local t
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        case "$t" in
            gui|cli) kept+=("$t") ;;
            *)       warn "发布/部署不支持目标：$t（已忽略）" ;;
        esac
    done
    [[ ${#kept[@]} -gt 0 ]] || die "没有可发布的目标。请用 --gui 或 --cli 指定。"
    KBM_TARGETS=("${kept[@]}")
}

# ---------------------------------------------------------------------------
# 源码仓库定位
# ---------------------------------------------------------------------------
kbm_is_source_repo() {
    local d="${1%/}"
    [[ -f "$d/KBManager.core/KBManager.core.csproj" ]] || return 1
    [[ -f "$d/KBManager.CLI/KBManager.CLI.csproj" ]] || return 1
    [[ -f "$d/KBManager.GUI/KBManager.GUI.csproj" ]] || return 1
    return 0
}

# 解析源码仓库位置：--source / KB_SOURCE 优先，否则在常见位置里找
kbm_find_source() {
    local -a candidates=()
    [[ -n "${KBM_SOURCE_DIR:-}" ]] && candidates+=("$KBM_SOURCE_DIR")
    candidates+=(
        "$PWD"
        "$KBM_BUILD_ROOT/../KBManager"
        "$KBM_BUILD_ROOT/KBManager"
        "$PWD/KBManager"
        "$PWD/.."
    )

    local d
    for d in "${candidates[@]}"; do
        [[ -d "$d" ]] || continue
        if kbm_is_source_repo "$d"; then
            KBM_SOURCE_DIR="$(cd -- "$d" && pwd -P)"
            return 0
        fi
    done
    return 1
}

kbm_set_project_paths() {
    KBM_PROJ_CORE="$KBM_SOURCE_DIR/KBManager.core/KBManager.core.csproj"
    KBM_PROJ_CLI="$KBM_SOURCE_DIR/KBManager.CLI/KBManager.CLI.csproj"
    KBM_PROJ_GUI="$KBM_SOURCE_DIR/KBManager.GUI/KBManager.GUI.csproj"
    KBM_PROJ_TESTS="$KBM_SOURCE_DIR/KBManager.Tests/KBManager.Tests.csproj"
}

kbm_resolve_source() {
    if kbm_find_source; then
        kbm_set_project_paths
        return 0
    fi

    if [[ -n "${KBM_SOURCE_DIR:-}" ]]; then
        die "指定的源码目录不是 KBManager 仓库：$KBM_SOURCE_DIR
    该目录应包含 KBManager.core/ KBManager.CLI/ KBManager.GUI/ 三个子项目。"
    fi
    die "找不到 KBManager 源码仓库。请用下列任一方式指定：
    ./build.sh doctor --source /path/to/KBManager
    export KB_SOURCE=/path/to/KBManager
    echo 'KB_SOURCE=/path/to/KBManager' >> $KBM_BUILD_ROOT/build.env"
}

kbm_require_source() {
    kbm_resolve_source
}

# target 名 → 子目录名
kbm_proj_dir() {
    case "$1" in
        core)  printf '%s' "KBManager.core" ;;
        cli)   printf '%s' "KBManager.CLI" ;;
        gui)   printf '%s' "KBManager.GUI" ;;
        tests) printf '%s' "KBManager.Tests" ;;
        *)     die "未知目标：$1" ;;
    esac
}

# target 名 → 项目文件
kbm_proj_path() {
    case "$1" in
        core)  printf '%s' "$KBM_PROJ_CORE" ;;
        cli)   printf '%s' "$KBM_PROJ_CLI" ;;
        gui)   printf '%s' "$KBM_PROJ_GUI" ;;
        tests) printf '%s' "$KBM_PROJ_TESTS" ;;
        *)     die "未知目标：$1" ;;
    esac
}

# ---------------------------------------------------------------------------
# .NET SDK 定位
#
# kbm_find_dotnet 只查找并返回状态（doctor 用），kbm_resolve_dotnet 在其基础上
# 找不到就直接报错退出（真正要编译的命令用）。
# ---------------------------------------------------------------------------
kbm_find_dotnet() {
    local candidate

    if [[ -n "${KBM_DOTNET_BIN:-}" ]]; then
        if [[ ! -x "$KBM_DOTNET_BIN" ]]; then
            err "DOTNET_BIN 指向的文件不可执行：$KBM_DOTNET_BIN"
            return 1
        fi
    else
        for candidate in \
            "$(command -v dotnet 2>/dev/null || true)" \
            "${DOTNET_ROOT:-}/dotnet" \
            "$HOME/.dotnet/dotnet" \
            "$KBM_BUILD_ROOT/.dotnet/dotnet" \
            "${KBM_SOURCE_DIR:-}/.dotnet/dotnet"; do
            if [[ -n "$candidate" && -x "$candidate" ]]; then
                KBM_DOTNET_BIN="$candidate"
                break
            fi
        done
    fi

    [[ -n "${KBM_DOTNET_BIN:-}" ]] || return 1

    # 用户级安装必须显式指定 DOTNET_ROOT，系统安装则不需要
    local dotnet_dir
    dotnet_dir="$(dirname -- "$KBM_DOTNET_BIN")"
    case "$KBM_DOTNET_BIN" in
        "$HOME/.dotnet/dotnet"|"$KBM_BUILD_ROOT/.dotnet/dotnet"|"${KBM_SOURCE_DIR:-/nonexistent}/.dotnet/dotnet")
            export DOTNET_ROOT="$dotnet_dir"
            ;;
    esac
    export PATH="$dotnet_dir:$PATH"

    "$KBM_DOTNET_BIN" --list-sdks 2>/dev/null | grep -q '^[0-9]' || return 1
    KBM_DOTNET_VERSION="$("$KBM_DOTNET_BIN" --version 2>/dev/null || printf 'unknown')"
    return 0
}

kbm_resolve_dotnet() {
    if ! kbm_find_dotnet; then
        die "未找到可用的 .NET SDK。请先执行： $KBM_BUILD_ROOT/setup-wsl.sh"
    fi
}

# ---------------------------------------------------------------------------
# Windows 侧路径探测
# ---------------------------------------------------------------------------
kbm_win_mount_root() { printf '%s' "${KBM_WIN_MOUNT:-/mnt/c}"; }

# 找 Windows 用户目录（/mnt/c/Users/<name>，以 NTUSER.DAT 为准）
kbm_detect_windows_user_dir() {
    local mount; mount="$(kbm_win_mount_root)"
    local prefer="${KB_WINDOWS_USER:-${USER:-}}"
    local first="" d name

    for d in "$mount"/Users/*/; do
        [[ -f "${d}NTUSER.DAT" ]] || continue
        name="$(basename -- "$d")"
        case "$name" in
            Public|Default|"Default User"|"All Users"|defaultuser0) continue ;;
        esac
        if [[ -n "$prefer" && "${name,,}" == "${prefer,,}" ]]; then
            printf '%s' "${d%/}"
            return 0
        fi
        [[ -n "$first" ]] || first="${d%/}"
    done

    if [[ -n "$first" ]]; then
        printf '%s' "$first"
        return 0
    fi
    return 1
}

# WSL 路径 → Windows 路径
kbm_to_windows_path() {
    local p="$1"
    if have wslpath; then
        local out
        if out="$(wslpath -w "$p" 2>/dev/null)" && [[ -n "$out" ]]; then
            printf '%s' "$out"
            return 0
        fi
    fi
    if [[ "$p" =~ ^/mnt/([a-zA-Z])/(.*)$ ]]; then
        printf '%s:\\%s' "${BASH_REMATCH[1]^^}" "${BASH_REMATCH[2]//\//\\}"
        return 0
    fi
    printf '%s' "$p"
}

kbm_windows_cmd() {
    if have cmd.exe; then
        command -v cmd.exe
    elif [[ -x /mnt/c/Windows/System32/cmd.exe ]]; then
        printf '%s' /mnt/c/Windows/System32/cmd.exe
    else
        return 1
    fi
}

kbm_win_dotnet() {
    local c
    for c in \
        "$(kbm_win_mount_root)/Program Files/dotnet/dotnet.exe" \
        "$(kbm_win_mount_root)/Program Files (x86)/dotnet/dotnet.exe"; do
        [[ -x "$c" ]] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# 产物校验 / 构建信息 / 打包
# ---------------------------------------------------------------------------
# 按 RID 推断原生库命名（LibGit2Sharp.NativeBinaries 的实际文件名）
# win / linux 是项目 .csproj 里显式复制的目标，缺失即视为发布失败；
# 其他 RID 只警告，避免挡住实验性的发布。
kbm_native_expectations() {
    KBM_NATIVE_GIT=""
    KBM_NATIVE_GIT_REQUIRED=0
    case "${KBM_RID:-}" in
        win-*)   KBM_NATIVE_GIT='git2-*.dll:libgit2 原生库'; KBM_NATIVE_GIT_REQUIRED=1 ;;
        linux-*) KBM_NATIVE_GIT='libgit2-*.so:libgit2 原生库'; KBM_NATIVE_GIT_REQUIRED=1 ;;
        osx-*)   KBM_NATIVE_GIT='libgit2-*.dylib:libgit2 原生库' ;;
    esac
}

kbm_verify_artifacts() {
    local out="$1"
    local missing=0 t dir
    kbm_native_expectations

    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        dir="$out/$t"
        [[ -d "$dir" ]] || { warn "缺少产物目录：$dir"; missing=1; continue; }

        case "$t" in
            gui)
                [[ -f "$dir/KBManager.GUI.exe" || -f "$dir/KBManager.GUI" ]] \
                    || { warn "缺少 GUI 可执行文件"; missing=1; }
                [[ -f "$dir/KBManager.GUI.dll" ]] || { warn "缺少 KBManager.GUI.dll"; missing=1; }
                ;;
            cli)
                [[ -f "$dir/KBManager.CLI.exe" || -f "$dir/KBManager.CLI" ]] \
                    || { warn "缺少 CLI 可执行文件"; missing=1; }
                [[ -f "$dir/KBManager.CLI.dll" ]] || { warn "缺少 KBManager.CLI.dll"; missing=1; }
                ;;
        esac
        [[ -f "$dir/KBManager.core.dll" ]] || { warn "缺少 KBManager.core.dll（$t）"; missing=1; }

        # libgit2 是 Git 功能的硬依赖；win/linux 目标缺失直接算发布失败
        if [[ -n "$KBM_NATIVE_GIT" ]]; then
            local glob="${KBM_NATIVE_GIT%%:*}" desc="${KBM_NATIVE_GIT#*:}"
            if compgen -G "$dir/$glob" >/dev/null; then
                ok "$t：$desc $(basename -- "$(compgen -G "$dir/$glob" | head -n1)")"
            else
                warn "$t：未找到 $desc（$glob），Git 功能可能不可用"
                [[ "$KBM_NATIVE_GIT_REQUIRED" == "1" ]] && missing=1
            fi
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        die "发布产物不完整，请检查上面的警告。"
    fi

    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        dir="$out/$t"
        ok "$t：$(find "$dir" -type f | wc -l | tr -d ' ') 个文件，$(du -sh "$dir" | cut -f1)"
    done
}

kbm_git_info() {
    KBM_GIT_BRANCH=""
    KBM_GIT_COMMIT=""
    KBM_GIT_DIRTY=0
    have git || return 0
    git -C "$KBM_SOURCE_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 0
    KBM_GIT_BRANCH="$(git -C "$KBM_SOURCE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    KBM_GIT_COMMIT="$(git -C "$KBM_SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -n "$(git -C "$KBM_SOURCE_DIR" status --porcelain 2>/dev/null)" ]]; then
        KBM_GIT_DIRTY=1
    fi
}

kbm_write_build_info() {
    local out="$1"
    kbm_git_info
    local dirty_mark=""
    [[ "${KBM_GIT_DIRTY:-0}" == "1" ]] && dirty_mark=" (工作区有未提交改动)"

    local file="$out/build-info.txt"
    {
        printf 'build time     : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf 'source repo    : %s\n' "$KBM_SOURCE_DIR"
        printf 'git branch     : %s\n' "${KBM_GIT_BRANCH:-unknown}"
        printf 'git commit     : %s%s\n' "${KBM_GIT_COMMIT:-unknown}" "$dirty_mark"
        printf 'configuration  : %s\n' "$KBM_CONFIG"
        printf 'runtime id     : %s\n' "$KBM_RID"
        printf 'self-contained : %s\n' "$KBM_SELF_CONTAINED"
        printf 'dotnet sdk     : %s (%s)\n' "$KBM_DOTNET_VERSION" "$KBM_DOTNET_BIN"
        printf 'built by       : KBManager.Build\n'
    } > "$file"

    # GUI 目录里也放一份，方便在 Windows 上看这批产物对应哪个提交
    local t
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        [[ -d "$out/$t" ]] && cp -f "$file" "$out/$t/build-info.txt"
    done
    ok "构建信息：$file"
}

kbm_maybe_zip() {
    local out="$1"
    [[ "$KBM_ZIP" == "1" ]] || return 0

    kbm_git_info
    local stamp
    if [[ -n "${KBM_GIT_COMMIT:-}" ]]; then
        stamp="$KBM_GIT_COMMIT"
        [[ "${KBM_GIT_DIRTY:-0}" == "1" ]] && stamp="$stamp-dirty"
    else
        stamp="$(date '+%Y%m%d-%H%M%S')"
    fi
    local zipfile="$KBM_ARTIFACTS/KBManager-${KBM_RID}-${KBM_CONFIG}-${stamp}.zip"

    log "打包 $zipfile"
    if [[ "$KBM_DRY_RUN" == "1" ]]; then
        printf '%s  [dry-run]%s zip %s\n' "$KBM_C_YELLOW" "$KBM_C_RESET" "$zipfile" >&2
        return 0
    fi
    rm -f "$zipfile"
    if have zip; then
        ( cd -- "$out" && zip -qr "$zipfile" . ) || die "打包失败：$zipfile"
    elif have python3; then
        ( cd -- "$out" && python3 -m zipfile -c "$zipfile" . ) || die "打包失败：$zipfile"
    else
        warn "未安装 zip / python3，跳过打包"
        return 0
    fi
    ok "压缩包：$zipfile（$(du -h "$zipfile" | cut -f1)）"
}

# ---------------------------------------------------------------------------
# 打印产物与部署位置（供 deploy / doctor 复用）
# ---------------------------------------------------------------------------
# 每个目标最终落地的目录（deploy 可能因为文件被占用而改成带时间戳的目录）
declare -A KBM_DEPLOY_ACTUAL=()

kbm_print_where() {
    local dir="$1"
    local t actual exe
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        case "$t" in
            gui) exe="KBManager.GUI.exe" ;;
            cli) exe="KBManager.CLI.exe" ;;
            *)   exe="" ;;
        esac
        [[ -n "$exe" ]] || continue
        actual="${KBM_DEPLOY_ACTUAL[$t]:-$dir/$t}"
        printf '  %-4s: %s\\%s\n' "$t" "$(kbm_to_windows_path "$actual")" "$exe" >&2
    done
}
