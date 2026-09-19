# shellcheck shell=bash
#
# deploy —— 发布后把产物复制到 Windows 可见目录（默认 C:\Users\<用户>\KBManager-win）。
#
# 细节：
#   * 只替换目标目录下的 gui/ 与 cli/ 两个子目录，不动其他内容
#   * 保留 Windows 上已有的 theme.json（GUI 首次运行会生成，属于用户自定义）
#   * 若目标目录里的文件正被占用（GUI 还在运行），自动退化为带时间戳的目录，
#     而不是让整个部署失败

kbm_cmd_deploy() {
    if [[ "$KBM_SKIP_PUBLISH" != "1" ]]; then
        kbm_cmd_publish
    else
        kbm_require_source
    fi

    local src="$KBM_ARTIFACTS/$KBM_RID"
    [[ -d "$src" ]] || die "找不到产物目录：$src
    先执行 $KBM_BUILD_ROOT/build.sh publish"

    local dest="$KBM_DEPLOY_DIR"
    if [[ -z "$dest" ]]; then
        local base
        if ! base="$(kbm_detect_windows_user_dir)"; then
            die "无法定位 Windows 用户目录（在 $(kbm_win_mount_root)/Users 下没找到 NTUSER.DAT）。
    请显式指定： ./build.sh deploy --deploy-dir /mnt/d/KBManager-win"
        fi
        dest="$base/KBManager-win"
    fi
    KBM_DEPLOY_DIR="$dest"

    log "复制产物到 Windows：$dest"
    run mkdir -p "$dest"

    local t target
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        [[ -d "$src/$t" ]] || { warn "产物中缺少 $t，跳过"; continue; }
        target="$(kbm_deploy_one "$src/$t" "$dest")"
        KBM_DEPLOY_ACTUAL["$t"]="$target"
    done

    if [[ "$KBM_DRY_RUN" == "1" ]]; then
        log "（dry-run 结束，未实际复制）"
        return 0
    fi

    echo >&2
    log "部署完成，在 Windows 上运行："
    kbm_print_where "$dest"
    echo >&2
    echo "  资源管理器打开： $(kbm_to_windows_path "$dest")" >&2
    echo "  在 WSL 里直接启动 GUI： $KBM_BUILD_ROOT/build.sh run" >&2

    if [[ "$KBM_RUN_AFTER_DEPLOY" == "1" ]]; then
        kbm_launch_gui
    fi
}

# 复制单个子目录，尽量保留用户改动过的配置文件。
# 把最终落地的目录打印到 stdout，供调用方记录（日志都走 stderr）。
kbm_deploy_one() {
    local srcdir="$1" destroot="$2"
    local name; name="$(basename -- "$srcdir")"
    local target="$destroot/$name"

    # 需要在覆盖时保留的文件：先挪到临时目录，删完旧目录再放回来
    local -a preserve=(theme.json)
    local -a keep=()
    local keep_tmp="" f
    for f in "${preserve[@]}"; do
        [[ -f "$target/$f" ]] && keep+=("$target/$f")
    done
    if [[ ${#keep[@]} -gt 0 && "$KBM_DRY_RUN" != "1" ]]; then
        keep_tmp="$(mktemp -d)"
        for f in "${keep[@]}"; do
            cp -f "$f" "$keep_tmp/$(basename -- "$f")"
        done
    fi

    if [[ "$KBM_DRY_RUN" != "1" && -e "$target" ]] && ! rm -rf "$target" 2>/dev/null; then
        local alt
        alt="$destroot/$name-$(date '+%Y%m%d-%H%M%S')"
        warn "$target 被占用（GUI 可能还在运行），改为部署到 $(basename -- "$alt")"
        target="$alt"
    fi

    run mkdir -p "$target"
    if [[ "$KBM_DRY_RUN" == "1" ]]; then
        printf '%s  [dry-run]%s cp -r %s/. %s/\n' "$KBM_C_YELLOW" "$KBM_C_RESET" "$srcdir" "$target" >&2
        printf '%s' "$target"
        return 0
    fi

    cp -r "$srcdir/." "$target/"

    if [[ -n "$keep_tmp" ]]; then
        for f in "$keep_tmp"/*; do
            cp -f "$f" "$target/"
            ok "保留原有的 $(basename -- "$f")"
        done
        rm -rf "$keep_tmp"
    fi
    ok "$name → $target"
    printf '%s' "$target"
}

# 在 Windows 上启动 GUI（通过 WSL interop 调 cmd.exe start）
kbm_launch_gui() {
    local dir="${KBM_DEPLOY_ACTUAL[gui]:-$KBM_DEPLOY_DIR/gui}"
    local exe="$dir/KBManager.GUI.exe"

    if [[ "$KBM_DRY_RUN" == "1" ]]; then
        local dry_cmd
        dry_cmd="$(kbm_windows_cmd 2>/dev/null || printf 'cmd.exe')"
        printf '%s  [dry-run]%s %s /c start "" %s\n' \
            "$KBM_C_YELLOW" "$KBM_C_RESET" "$dry_cmd" "$(kbm_to_windows_path "$exe")" >&2
        return 0
    fi

    if [[ ! -f "$exe" ]]; then
        warn "找不到 $exe，无法启动 GUI"
        return 1
    fi

    local cmd_bin
    if ! cmd_bin="$(kbm_windows_cmd)"; then
        warn "当前环境不能调用 Windows 程序（未找到 cmd.exe），请手动双击："
        warn "  $(kbm_to_windows_path "$exe")"
        return 1
    fi

    local win_exe; win_exe="$(kbm_to_windows_path "$exe")"
    log "在 Windows 上启动：$win_exe"

    # 先切到 Windows 目录再调 cmd.exe，避免 UNC 工作目录告警
    ( cd -- "$(kbm_win_mount_root)" 2>/dev/null || cd / ; \
      "$cmd_bin" /c start "" "$win_exe" >/dev/null 2>&1 ) \
        || { warn "启动失败，请手动双击 $win_exe"; return 1; }
    ok "已通知 Windows 启动 GUI"
}
