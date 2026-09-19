# shellcheck shell=bash
#
# clean —— 清理编译输出。
#   clean          清理 dotnet 输出 + artifacts 目录
#   clean --deep   额外删除源码仓库里的 bin/ obj/

kbm_cmd_clean() {
    kbm_require_source
    kbm_resolve_dotnet

    log "清理编译输出 [$KBM_CONFIG]"
    local t proj dir
    for t in core cli gui tests; do
        proj="$(kbm_proj_path "$t")"
        [[ -f "$proj" ]] || continue
        dir="$(kbm_proj_dir "$t")"
        if [[ "$KBM_DEEP" == "1" ]]; then
            log "  删除 $t 的 bin/ obj/"
            run rm -rf "$KBM_SOURCE_DIR/$dir/bin" "$KBM_SOURCE_DIR/$dir/obj"
        else
            log "  clean $t"
            run "$KBM_DOTNET_BIN" clean "$proj" -c "$KBM_CONFIG" --nologo >/dev/null 2>&1 || true
        fi
    done

    log "删除产物目录 $KBM_ARTIFACTS"
    run rm -rf "$KBM_ARTIFACTS"
    ok "清理完成"
}
