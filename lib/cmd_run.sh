# shellcheck shell=bash
#
# run —— 部署到 Windows 后立刻启动 GUI，是「改代码 → 直接看界面」的最短路径。
# run-local —— 用 WSLg 在本机 Linux 侧跑 GUI，适合快速验证界面逻辑（不经过 Windows）。

kbm_cmd_run() {
    kbm_cmd_deploy

    local t
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        if [[ "$t" == "gui" ]]; then
            kbm_launch_gui
            return 0
        fi
    done
    warn "本次只发布了 --cli，没有 GUI 可以启动"
}

kbm_cmd_run_local() {
    KBM_RID="${KBM_RID_LOCAL:-linux-x64}"
    kbm_cmd_publish

    local exe="$KBM_ARTIFACTS/$KBM_RID/gui/KBManager.GUI"
    [[ -x "$exe" ]] || die "找不到可执行文件：$exe"

    if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        warn "没有检测到 DISPLAY / WAYLAND_DISPLAY，WSLg 可能不可用，GUI 窗口不会出现"
    fi

    log "在 WSL 里启动 GUI：$exe"
    if [[ "$KBM_DRY_RUN" == "1" ]]; then
        printf '%s  [dry-run]%s %s\n' "$KBM_C_YELLOW" "$KBM_C_RESET" "$exe" >&2
        return 0
    fi

    if have setsid; then
        setsid "$exe" >/dev/null 2>&1 < /dev/null &
    else
        nohup "$exe" >/dev/null 2>&1 < /dev/null &
    fi
    ok "已启动（进程号 $!）；若窗口没有出现，检查 WSLg 是否正常"
}
