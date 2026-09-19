# shellcheck shell=bash
#
# doctor —— 打印整条链路的环境信息，用来定位「为什么编译/部署失败」。
# 输出到 stdout，方便重定向或贴给别人看。

# 近似显示宽度：ASCII 记 1 列，其余（中文等）记 2 列，用于让标签对齐
kbm_display_width() {
    local s="$1" out=0 i c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        if [[ "$c" == [!\ -~] ]]; then
            out=$((out + 2))
        else
            out=$((out + 1))
        fi
    done
    printf '%s' "$out"
}

kbm_doctor_line() {
    local label="$1" value="$2" width
    width="$(kbm_display_width "$label")"
    printf '  %s%*s %s\n' "$label" $((18 - width)) '' "$value"
}

kbm_cmd_doctor() {
    local mount; mount="$(kbm_win_mount_root)"

    printf '== KBManager.Build ==\n'
    kbm_doctor_line "工具目录" "$KBM_BUILD_ROOT"
    kbm_doctor_line "本地配置" "${KBM_CONFIG_FILE:-（未使用 build.env）}"
    kbm_doctor_line "产物根目录" "$KBM_ARTIFACTS"
    kbm_doctor_line "当前参数" "config=$KBM_CONFIG rid=$KBM_RID self-contained=$KBM_SELF_CONTAINED targets=${KBM_TARGETS[*]}"

    printf '\n== 源码仓库 ==\n'
    if kbm_find_source; then
        kbm_set_project_paths
        kbm_doctor_line "位置" "$KBM_SOURCE_DIR"
        local t mark
        for t in core cli gui tests; do
            if [[ -f "$(kbm_proj_path "$t")" ]]; then mark="存在"; else mark="缺失"; fi
            kbm_doctor_line "$t" "$(kbm_proj_dir "$t") — $mark"
        done
        if [[ -f "$KBM_SOURCE_DIR/KBManager.slnx" ]]; then
            kbm_doctor_line "解决方案" "KBManager.slnx（SLNX 需 SDK 9.0.200+；本工具按项目逐个编译）"
        fi
        if have git && git -C "$KBM_SOURCE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
            kbm_git_info
            local dirty="工作区干净"
            [[ "$KBM_GIT_DIRTY" == "1" ]] && dirty="有未提交改动"
            kbm_doctor_line "Git" "分支 ${KBM_GIT_BRANCH:-?}  提交 ${KBM_GIT_COMMIT:-?}  $dirty"
        fi
    else
        kbm_doctor_line "位置" "未找到（用 --source 或 KB_SOURCE 指定）"
    fi

    printf '\n== .NET SDK（WSL 侧）==\n'
    if kbm_find_dotnet 2>/dev/null; then
        kbm_doctor_line "可执行文件" "$KBM_DOTNET_BIN"
        kbm_doctor_line "版本" "$KBM_DOTNET_VERSION"
        kbm_doctor_line "DOTNET_ROOT" "${DOTNET_ROOT:-（未设置，使用系统安装）}"
        local line
        while IFS= read -r line; do
            [[ -n "$line" ]] && kbm_doctor_line "SDK" "$line"
        done < <("$KBM_DOTNET_BIN" --list-sdks 2>/dev/null)
        while IFS= read -r line; do
            [[ -n "$line" ]] && kbm_doctor_line "运行时" "$line"
        done < <("$KBM_DOTNET_BIN" --list-runtimes 2>/dev/null | grep 'Microsoft.NETCore.App')
    else
        kbm_doctor_line "状态" "未找到 SDK，请运行 $KBM_BUILD_ROOT/setup-wsl.sh"
    fi

    printf '\n== WSL 环境 ==\n'
    kbm_doctor_line "发行版" "${WSL_DISTRO_NAME:-（非 WSL 或未设置）}"
    kbm_doctor_line "内核" "$(uname -r)"
    kbm_doctor_line "显示" "DISPLAY=${DISPLAY:-<空>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<空>}（run-local 需要 WSLg）"

    printf '\n== Windows 侧 ==\n'
    kbm_doctor_line "挂载点" "$mount"
    local base
    if base="$(kbm_detect_windows_user_dir)"; then
        kbm_doctor_line "用户目录" "$base  ($(kbm_to_windows_path "$base"))"
        kbm_doctor_line "默认部署目录" "$(kbm_to_windows_path "${KBM_DEPLOY_DIR:-$base/KBManager-win}")"
    else
        kbm_doctor_line "用户目录" "未找到（$mount/Users 下没有 NTUSER.DAT）"
    fi

    local cmd_bin
    if cmd_bin="$(kbm_windows_cmd)"; then
        kbm_doctor_line "cmd.exe" "$cmd_bin（可调用 Windows 程序）"
    else
        kbm_doctor_line "cmd.exe" "不可用 —— deploy --run 无法自动启动 GUI"
    fi

    local win_dotnet
    if win_dotnet="$(kbm_win_dotnet)"; then
        kbm_doctor_line "dotnet.exe" "$(kbm_to_windows_path "$win_dotnet")"
        local sdk_list runtime_list
        sdk_list="$( cd -- "$mount" 2>/dev/null && timeout 30 "$win_dotnet" --list-sdks 2>/dev/null || true )"
        runtime_list="$( cd -- "$mount" 2>/dev/null && timeout 30 "$win_dotnet" --list-runtimes 2>/dev/null | grep 'Microsoft.NETCore.App' || true )"
        if [[ -n "$sdk_list" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && kbm_doctor_line "SDK" "$line"
            done <<< "$sdk_list"
        fi
        if [[ -n "$runtime_list" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && kbm_doctor_line "运行时" "$line"
            done <<< "$runtime_list"
        fi
        if printf '%s' "$runtime_list" | grep -q 'Microsoft.NETCore.App 8\.'; then
            kbm_doctor_line "框架依赖发布" "Windows 上已有 .NET 8 运行时，可直接运行"
        else
            kbm_doctor_line "框架依赖发布" "缺少 .NET 8 运行时，请改用 publish/deploy --self-contained"
        fi
    else
        kbm_doctor_line "dotnet.exe" "未在 $mount 下找到 Windows 版 .NET"
    fi

    printf '\n== 当前产物 ==\n'
    local out="$KBM_ARTIFACTS/$KBM_RID"
    if [[ -d "$out" ]]; then
        kbm_doctor_line "目录" "$out"
        for t in gui cli; do
            [[ -d "$out/$t" ]] && kbm_doctor_line "$t" "$(find "$out/$t" -type f | wc -l | tr -d ' ') 个文件"
        done
        if [[ -f "$out/build-info.txt" ]]; then
            printf '\n'
            sed 's/^/  /' "$out/build-info.txt"
        fi
        kbm_doctor_line "Windows 路径" "$(kbm_to_windows_path "$out")"
    else
        kbm_doctor_line "目录" "$out（尚未发布）"
    fi
}
