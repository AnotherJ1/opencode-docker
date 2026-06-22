#!/usr/bin/env bash
# OpenCode 镜像本地构建脚本
#
# 用法：
#   ./build.sh                  # 构建最新版（latest）
#   ./build.sh 1.2.5            # 构建指定版本
#   ./build.sh 1.2.5 multi      # 构建指定版本 + 多架构（需要 buildx）
#   ./build.sh latest multi     # 构建最新版多架构
#   ./build.sh --list           # 查看 npm 上可用的版本
#
# 构建后的镜像：
#   - 单架构: opencode:local 或 opencode:<版本>-local
#   - 多架构: 仅推送到本地 registry 时有效，默认只 load 到 docker
#
# 环境变量：
#   OPENCODE_VERSION  覆盖默认版本
#   BUILD_PLATFORMS   多架构平台列表，默认 linux/amd64,linux/arm64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
hint()   { echo -e "${BLUE}[HINT]${NC} $*"; }

# 默认值
DEFAULT_PLATFORMS="linux/amd64,linux/arm64"

# ============== 工具函数 ==============

# 检查前置依赖
check_prereqs() {
    command -v docker >/dev/null 2>&1 || error "未安装 docker"
}

# 检查 buildx 是否可用
has_buildx() {
    docker buildx version >/dev/null 2>&1
}

# 查询 npm 上的 opencode-ai 所有版本
list_versions() {
    info "查询 npm 上 opencode-ai 可用版本（最近 20 个）..."
    if ! command -v npm >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
        warn "本机无 npm/npx，尝试通过 docker 查询"
        docker run --rm node:24-alpine sh -c "npm view opencode-ai versions --json | tail -30"
    else
        npm view opencode-ai versions --json 2>/dev/null | tail -30
    fi
}

# 单架构构建
build_single() {
    local version="$1"
    local tag="$2"

    info "单架构构建: opencode-ai@${version} -> ${tag}"
    docker build \
        --build-arg OPENCODE_VERSION="${version}" \
        -t "${tag}" \
        -f Dockerfile \
        .

    info "构建完成: ${tag}"
    docker images "${tag}"
}

# 多架构构建（需要 buildx，且仅推送到 registry 时才同时支持两架构，本地 load 只支持当前架构）
build_multi() {
    local version="$1"
    local tag="$2"
    local platforms="${BUILD_PLATFORMS:-$DEFAULT_PLATFORMS}"

    has_buildx || error "未安装 docker buildx，无法多架构构建。请安装: https://github.com/docker/buildx"

    info "多架构构建: opencode-ai@${version} -> ${tag} (${platforms})"

    # 检查 buildx builder
    if ! docker buildx inspect default >/dev/null 2>&1; then
        warn "默认 builder 不存在，创建中..."
        docker buildx create --use --name opencode-builder
        docker buildx inspect --bootstrap
    fi

    # 注意：多架构构建不支持 --load，只能 --push 到 registry 或 --output type=docker（单架构）
    # 这里采用 --output type=docker，只 load 当前平台镜像，方便本地使用
    # 如需推送到 registry，请改用 --push 并设置完整 registry 地址

    echo ""
    warn "多架构构建说明："
    echo "  - docker buildx 多架构构建无法直接 --load 到本地 docker（同时支持多架构）"
    echo "  - 已切换为 --output type=docker，仅 load 当前主机架构镜像"
    echo "  - 如需多架构镜像推送 registry，请手动执行："
    echo ""
    echo "    docker buildx build \\"
    echo "      --platform ${platforms} \\"
    echo "      --build-arg OPENCODE_VERSION=${version} \\"
    echo "      -t <registry>/${tag} \\"
    echo "      --push ."
    echo ""

    # 实际执行：只 load 当前平台
    docker buildx build \
        --platform "${platforms}" \
        --build-arg OPENCODE_VERSION="${version}" \
        -t "${tag}" \
        --output type=docker \
        -f Dockerfile \
        .

    info "多架构构建完成（已 load 当前平台镜像）: ${tag}"
    docker images "${tag}"
}

# ============== 主入口 ==============

main() {
    check_prereqs

    local arg="${1:-}"
    local multi="false"

    # 处理 --list
    if [[ "$arg" == "--list" || "$arg" == "-l" ]]; then
        list_versions
        exit 0
    fi

    # 处理 help（无参数时默认构建 latest，不显示 help）
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        cat <<EOF
OpenCode 镜像本地构建脚本

用法:
  ./build.sh                    构建 latest 版本（单架构）
  ./build.sh <version>          构建指定版本（单架构）
  ./build.sh <version> multi    构建指定版本（多架构，需要 buildx）
  ./build.sh --list             查看 npm 上 opencode-ai 可用版本

示例:
  ./build.sh                    # opencode:local (latest)
  ./build.sh 1.2.5              # opencode:1.2.5-local
  ./build.sh 1.2.5 multi        # 多架构构建
  ./build.sh latest multi       # 多架构 latest

环境变量:
  OPENCODE_VERSION    覆盖默认版本（如 OPENCODE_VERSION=1.2.5 ./build.sh）
  BUILD_PLATFORMS     多架构平台，默认 linux/amd64,linux/arm64

说明:
  - 单架构构建通过 docker build 直接完成，结果 load 到本地
  - 多架构构建通过 docker buildx，但 --output type=docker 只能 load 当前平台
  - 如需推送多架构镜像到 registry，请手动使用 docker buildx build --push

查看可用版本:
  ./build.sh --list
  或访问 https://www.npmjs.com/package/opencode-ai
EOF
        exit 0
    fi

    # 解析参数
    local version="latest"
    if [[ -n "$arg" ]]; then
        version="$arg"
        shift
    fi
    # 检查是否多架构
    if [[ "${1:-}" == "multi" ]]; then
        multi="true"
    fi

    # 环境变量覆盖
    version="${OPENCODE_VERSION:-$version}"

    # 生成 tag
    local tag
    if [[ "$version" == "latest" ]]; then
        tag="opencode:local"
    else
        tag="opencode:${version}-local"
    fi

    info "准备构建 opencode-ai@${version}"
    info "镜像 tag: ${tag}"
    echo ""

    if [[ "$multi" == "true" ]]; then
        build_multi "$version" "$tag"
    else
        build_single "$version" "$tag"
    fi

    echo ""
    info "构建成功！"
    hint "下一步："
    echo "  1. 编辑 .env（如尚未创建，参考 .env.sample）"
    echo "  2. 启动服务: ./deploy.sh start"
    echo ""
    hint "如使用指定版本构建，请同步修改 docker-compose.yml 中的 image 为: ${tag}"
}

main "$@"
