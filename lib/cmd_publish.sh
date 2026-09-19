# shellcheck shell=bash
#
# publish —— 从 WSL 直接交叉编译出 Windows x64 可执行产物。
#
# 产物结构：
#   artifacts/<rid>/
#   ├── gui/   KBManager.GUI.exe + 依赖 + 原生库
#   ├── cli/   KBManager.CLI.exe + 依赖 + 原生库
#   └── build-info.txt
#
# 发布模式：
#   * 默认「框架依赖」：体积小，Windows 上需要 .NET 8 运行时
#   * --self-contained：约 70~90 MB，Windows 上无需安装任何东西

kbm_cmd_publish() {
    kbm_require_source
    kbm_resolve_dotnet
    kbm_keep_app_targets

    local out="$KBM_ARTIFACTS/$KBM_RID"
    local mode_desc
    if [[ "$KBM_SELF_CONTAINED" == "1" ]]; then
        mode_desc="自包含（目标机无需安装 .NET）"
    else
        mode_desc="框架依赖（目标机需要 .NET 8 运行时）"
    fi

    local -a sc_flag=(--self-contained false)
    [[ "$KBM_SELF_CONTAINED" == "1" ]] && sc_flag=(--self-contained true)
    local -a restore_flag=()
    [[ "$KBM_NO_RESTORE" == "1" ]] && restore_flag=(--no-restore)

    log "发布 $KBM_RID [$KBM_CONFIG] —— $mode_desc"
    log "  产物目录：$out"

    if [[ "$KBM_DRY_RUN" != "1" ]]; then
        # 每次全量重建产物目录，避免上一次的残留文件混进来
        rm -rf "$out"
        mkdir -p "$out"
    fi

    local t proj
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        proj="$(kbm_proj_path "$t")"
        if [[ ! -f "$proj" ]]; then
            warn "跳过不存在的项目：$proj"
            continue
        fi
        log "  publish $t"
        run "$KBM_DOTNET_BIN" publish "$proj" \
            -c "$KBM_CONFIG" \
            -r "$KBM_RID" \
            ${sc_flag[@]+"${sc_flag[@]}"} \
            ${restore_flag[@]+"${restore_flag[@]}"} \
            ${KBM_EXTRA_ARGS[@]+"${KBM_EXTRA_ARGS[@]}"} \
            -o "$out/$t" \
            --nologo
        ok "$t 发布完成"
    done

    if [[ "$KBM_DRY_RUN" == "1" ]]; then
        log "（dry-run 结束，未实际执行发布）"
        return 0
    fi

    kbm_verify_artifacts "$out"
    kbm_write_build_info "$out"
    kbm_maybe_zip "$out"

    log "产物目录：$out"
}
