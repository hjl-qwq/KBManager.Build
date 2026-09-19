#!/usr/bin/env bash
#
# KBManager.Build —— 在 WSL 里编译 KBManager，并把 Windows 产物送到 C 盘上测试 GUI。
#
#   ./build.sh doctor    看看环境对不对
#   ./build.sh deploy    编译 + 交叉发布 + 复制到 Windows
#   ./build.sh run       上一条 + 直接在 Windows 上启动 GUI
#
# 详细说明见 README.md。
#
set -euo pipefail

KBM_BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
KBM_VERSION="0.1.0"

# shellcheck source=lib/common.sh
source "$KBM_BUILD_ROOT/lib/common.sh"
# shellcheck source=lib/cmd_build.sh
source "$KBM_BUILD_ROOT/lib/cmd_build.sh"
# shellcheck source=lib/cmd_test.sh
source "$KBM_BUILD_ROOT/lib/cmd_test.sh"
# shellcheck source=lib/cmd_publish.sh
source "$KBM_BUILD_ROOT/lib/cmd_publish.sh"
# shellcheck source=lib/cmd_deploy.sh
source "$KBM_BUILD_ROOT/lib/cmd_deploy.sh"
# shellcheck source=lib/cmd_run.sh
source "$KBM_BUILD_ROOT/lib/cmd_run.sh"
# shellcheck source=lib/cmd_doctor.sh
source "$KBM_BUILD_ROOT/lib/cmd_doctor.sh"
# shellcheck source=lib/cmd_clean.sh
source "$KBM_BUILD_ROOT/lib/cmd_clean.sh"

# 这些开关可能被命令行提前设置，先初始化以适配 set -u
KBM_TARGETS=()
KBM_EXTRA_ARGS=()

usage() {
    cat <<'EOF'
KBManager.Build —— WSL 编译，Windows 测试

用法：
  ./build.sh <命令> [选项]

命令：
  doctor      打印整条链路的环境信息（SDK、源码位置、Windows 路径、运行时）
  build       在当前平台编译 core + CLI + GUI（默认目标）
  restore     只做 NuGet 还原
  test        运行 KBManager.Tests 的 xUnit 测试
  publish     交叉编译 Windows 产物到 artifacts/<rid>/{gui,cli}
  deploy      publish + 复制到 Windows 可见目录
  run         deploy + 在 Windows 上启动 GUI（最短验证路径）
  run-local   发布 linux-x64 并用 WSLg 在本机跑 GUI
  release     test + deploy，提交前跑这个
  clean       清理编译输出与 artifacts（--deep 连 bin/obj 一起删）
  help        显示本帮助

选项：
  -C, --source DIR        指定 KBManager 源码仓库位置（默认自动查找）
  -c, --config NAME       构建配置 Debug|Release（默认 Release）
      --rid RID           目标运行时（默认 win-x64）
  -o, --out DIR           产物根目录（默认 <本仓库>/artifacts）
      --deploy-dir DIR    deploy 落地目录，WSL 路径写法（默认 C:\Users\<用户>\KBManager-win）
  -s, --self-contained    自包含发布，目标机不需要 .NET
      --framework-dependent  框架依赖发布（默认）
      --gui / --cli       只处理指定目标（默认两者都处理）
      --all-targets       两个目标都处理
      --zip               额外打一个 zip 包到 artifacts/
      --with-tests        build 时把测试项目一起编译
      --no-restore        传给 dotnet 的 --no-restore（跳过多余还原）
      --no-publish        deploy/run 时跳过发布，直接用现有产物
      --run               deploy 完成后启动 GUI（等价于 run）
      --deep              clean 时删除源码仓库里的 bin/obj
  -v, --verbose           回显实际执行的命令
  -n, --dry-run           只打印会做什么，不真正执行
  -h, --help              显示帮助
      --version           显示版本
  --                      后面的参数原样透传给 dotnet

环境变量（优先级低于命令行，高于 build.env）：
  KB_SOURCE               源码仓库路径
  CONFIG                  构建配置，默认 Release
  RID                     目标运行时，默认 win-x64
  ARTIFACTS               产物根目录
  WIN_DEPLOY_DIR          deploy 落地目录
  SELF_CONTAINED=1        自包含发布
  DOTNET_BIN              指定 dotnet 可执行文件
  NUGET_PACKAGES          NuGet 包缓存目录
  KB_WINDOWS_USER         指定 Windows 用户名（默认取当前用户）
  KB_WIN_MOUNT            Windows 挂载点，默认 /mnt/c

示例：
  ./build.sh doctor
  ./build.sh deploy
  ./build.sh run
  CONFIG=Debug ./build.sh run
  ./build.sh deploy --self-contained --zip
  ./build.sh deploy -C ~/src/KBManager --deploy-dir /mnt/d/KBManager-win
  ./build.sh clean --deep
EOF
}

main() {
    local cmd=""
    local -a words=()
    local cli_source="" cli_config="" cli_rid="" cli_out="" cli_deploy="" cli_sc=""
    local -a cli_targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -C|--source)          cli_source="${2:?--source 需要一个目录}"; shift 2 ;;
            -c|--config|--configuration) cli_config="${2:?--config 需要 Debug 或 Release}"; shift 2 ;;
            --rid)                cli_rid="${2:?--rid 需要一个 RID}"; shift 2 ;;
            -o|--out|--artifacts) cli_out="${2:?--out 需要一个目录}"; shift 2 ;;
            --deploy-dir)         cli_deploy="${2:?--deploy-dir 需要一个目录}"; shift 2 ;;
            -s|--self-contained)  cli_sc="1"; shift ;;
            --framework-dependent) cli_sc="0"; shift ;;
            --gui)                cli_targets+=(gui); shift ;;
            --cli)                cli_targets+=(cli); shift ;;
            --core)               cli_targets+=(core); shift ;;
            --all-targets)        cli_targets=(gui cli); shift ;;
            --zip)                KBM_ZIP=1; shift ;;
            --deep)               KBM_DEEP=1; shift ;;
            --with-tests)         KBM_WITH_TESTS=1; shift ;;
            --no-restore)         KBM_NO_RESTORE=1; shift ;;
            --no-publish)         KBM_SKIP_PUBLISH=1; shift ;;
            --run)                KBM_RUN_AFTER_DEPLOY=1; shift ;;
            -v|--verbose)         KBM_VERBOSE=1; shift ;;
            -n|--dry-run)         KBM_DRY_RUN=1; shift ;;
            -h|--help)            usage; exit 0 ;;
            --version)            printf 'KBManager.Build %s\n' "$KBM_VERSION"; exit 0 ;;
            --)                   shift; KBM_EXTRA_ARGS+=("$@"); break ;;
            -*)                   die "未知选项：$1（用 -h 查看用法）" ;;
            *)                    words+=("$1"); shift ;;
        esac
    done

    cmd="${words[0]:-help}"
    if [[ ${#words[@]} -gt 1 ]]; then
        die "一次只能执行一个命令，收到：${words[*]}"
    fi

    kbm_load_config

    # 命令行参数最后应用，优先级最高
    [[ -n "$cli_source" ]] && KBM_SOURCE_DIR="$cli_source"
    [[ -n "$cli_config" ]] && KBM_CONFIG="$cli_config"
    [[ -n "$cli_rid" ]] && KBM_RID="$cli_rid"
    [[ -n "$cli_out" ]] && KBM_ARTIFACTS="$cli_out"
    [[ -n "$cli_deploy" ]] && KBM_DEPLOY_DIR="$cli_deploy"
    [[ -n "$cli_sc" ]] && KBM_SELF_CONTAINED="$cli_sc"
    [[ ${#cli_targets[@]} -gt 0 ]] && KBM_TARGETS=("${cli_targets[@]}")

    case "$cmd" in
        doctor)     kbm_cmd_doctor ;;
        build)      kbm_cmd_build ;;
        restore)    kbm_cmd_restore ;;
        test)       kbm_cmd_test ;;
        publish)    kbm_cmd_publish ;;
        deploy)     kbm_cmd_deploy ;;
        run)        kbm_cmd_run ;;
        run-local)  kbm_cmd_run_local ;;
        release)    kbm_cmd_test; kbm_cmd_deploy ;;
        clean)      kbm_cmd_clean ;;
        help)       usage ;;
        *)          die "未知命令：$cmd（用 -h 查看用法）" ;;
    esac
}

main "$@"
