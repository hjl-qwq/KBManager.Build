# shellcheck shell=bash
#
# restore / build —— 在当前平台（WSL/Linux）编译源码，验证代码能否通过编译。
#
# 说明：KBManager.slnx 使用的是新的 SLNX 格式（需要 .NET SDK 9.0.200+），
# 而本项目面向 .NET 8 SDK，因此按项目逐个编译，和仓库 CI 的做法保持一致。

kbm_cmd_restore() {
    kbm_require_source
    kbm_resolve_dotnet

    log "还原 NuGet 依赖 [$KBM_CONFIG]"
    local t proj
    for t in core cli gui tests; do
        proj="$(kbm_proj_path "$t")"
        [[ -f "$proj" ]] || { warn "跳过不存在的项目：$proj"; continue; }
        log "  restore $t"
        run "$KBM_DOTNET_BIN" restore "$proj" --nologo \
            ${KBM_EXTRA_ARGS[@]+"${KBM_EXTRA_ARGS[@]}"}
    done
    ok "依赖还原完成"
}

kbm_cmd_build() {
    kbm_require_source
    kbm_resolve_dotnet

    local -a restore_flag=()
    [[ "$KBM_NO_RESTORE" == "1" ]] && restore_flag=(--no-restore)

    log "编译 [$KBM_CONFIG]  dotnet $KBM_DOTNET_VERSION"
    log "  源码：$KBM_SOURCE_DIR"

    # core 先编译，避免 GUI / CLI 同时还原时的竞态
    local -a order=(core)
    local t
    for t in ${KBM_TARGETS[@]+"${KBM_TARGETS[@]}"}; do
        [[ "$t" == "core" ]] || order+=("$t")
    done
    [[ "$KBM_WITH_TESTS" == "1" ]] && order+=(tests)

    local proj
    for t in "${order[@]}"; do
        proj="$(kbm_proj_path "$t")"
        if [[ ! -f "$proj" ]]; then
            warn "跳过不存在的项目：$proj"
            continue
        fi
        log "  build $t"
        run "$KBM_DOTNET_BIN" build "$proj" -c "$KBM_CONFIG" \
            ${restore_flag[@]+"${restore_flag[@]}"} \
            ${KBM_EXTRA_ARGS[@]+"${KBM_EXTRA_ARGS[@]}"} \
            --nologo
        ok "$t 编译通过"
    done

    log "全部编译通过"
}
