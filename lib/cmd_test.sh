# shellcheck shell=bash
#
# test —— 运行 KBManager.Tests 里的 xUnit 测试。
# 测试跑在 WSL 上（net8.0，跨平台），不需要 Windows。

kbm_cmd_test() {
    kbm_require_source
    kbm_resolve_dotnet

    local proj="$KBM_PROJ_TESTS"
    [[ -f "$proj" ]] || die "找不到测试项目：$proj"

    local -a restore_flag=()
    [[ "$KBM_NO_RESTORE" == "1" ]] && restore_flag=(--no-restore)

    log "运行单元测试 [$KBM_CONFIG]"
    run "$KBM_DOTNET_BIN" test "$proj" -c "$KBM_CONFIG" \
        ${restore_flag[@]+"${restore_flag[@]}"} \
        ${KBM_EXTRA_ARGS[@]+"${KBM_EXTRA_ARGS[@]}"} \
        --nologo
    ok "测试完成"
}
