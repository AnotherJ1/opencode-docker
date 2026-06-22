#!/usr/bin/env bash
# OpenCode 一键部署脚本
# 反代/HTTPS 由外部 nginx 自行配置，指向 127.0.0.1:4096
#
# 使用方式：
#   1. 把整个 opencode-docker 目录上传到服务器
#   2. cd opencode-docker
#   3. chmod +x deploy.sh
#   4. ./deploy.sh init    # 首次初始化（生成 .env）
#   5. ./deploy.sh build   # 本地构建 opencode 镜像
#   6. ./deploy.sh start   # 启动
#   7. ./deploy.sh status  # 查看状态
#   8. ./deploy.sh logs    # 查看日志
#   9. ./deploy.sh update  # 重新构建并升级到最新版

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ============== 前置检查 ==============
check_prereqs() {
    command -v docker >/dev/null 2>&1 || error "未安装 docker"
    command -v docker compose >/dev/null 2>&1 || error "未安装 docker compose (需要 Docker Compose v2)"
}

# ============== 子命令 ==============

# 首次初始化（只生成 .env 和目录，不再处理域名/证书）
cmd_init() {
    info "OpenCode 首次部署初始化"
    echo ""

    # 1. 生成 .env
    if [[ ! -f "$ENV_FILE" ]]; then
        cp "$SCRIPT_DIR/.env.sample" "$ENV_FILE"
        # 生成随机密码
        local rand_pass
        rand_pass="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s/change_me_to_a_strong_password/${rand_pass}/" "$ENV_FILE"
        else
            sed -i "s/change_me_to_a_strong_password/${rand_pass}/" "$ENV_FILE"
        fi
        chmod 600 "$ENV_FILE"
        info "已生成 .env（含自动随机密码）: $ENV_FILE"
        info "请按需编辑用户名: nano $ENV_FILE"
    else
        warn ".env 已存在，跳过"
    fi

    # 2. 创建数据目录
    mkdir -p "$SCRIPT_DIR/data/share" "$SCRIPT_DIR/data/state" "$SCRIPT_DIR/data/config"
    info "已创建数据目录: data/"

    echo ""
    info "初始化完成。接下来："
    echo "  ./deploy.sh build    # 构建镜像"
    echo "  ./deploy.sh start    # 启动服务"
    echo ""
    warn "外部 nginx 反代需自行配置，指向 127.0.0.1:4096"
}

# 本地构建镜像（转发到 build.sh）
# 无参数时默认构建 latest
cmd_build() {
    local build_script="$SCRIPT_DIR/build.sh"
    [[ -x "$build_script" ]] || chmod +x "$build_script"
    if [[ $# -eq 0 ]]; then
        "$build_script" latest
    else
        "$build_script" "$@"
    fi
}

# 启动
cmd_start() {
    check_prereqs
    [[ -f "$ENV_FILE" ]] || error ".env 不存在，请先 ./deploy.sh init"
    info "启动 OpenCode"
    docker compose up -d
    info "启动完成"
    cmd_status
}

# 停止
cmd_stop() {
    info "停止服务"
    docker compose down
}

# 重启
cmd_restart() {
    info "重启服务"
    docker compose restart
}

# 状态
cmd_status() {
    docker compose ps
}

# 日志
cmd_logs() {
    docker compose logs -f --tail=100
}

# 升级（重新构建 latest）
cmd_update() {
    info "升级 opencode 镜像（本地重新构建 latest）"
    local build_script="$SCRIPT_DIR/build.sh"
    [[ -x "$build_script" ]] || chmod +x "$build_script"
    "$build_script" latest
    info "重启以应用更新"
    docker compose up -d --force-recreate opencode
    info "升级完成"
    cmd_status
}

# 帮助
cmd_help() {
    cat <<EOF
OpenCode 部署脚本（反代/HTTPS 由外部 nginx 自行配置）

用法:
  ./deploy.sh <command> [args...]

命令:
  init    首次初始化（生成 .env、创建数据目录）
  build   本地构建 opencode 镜像（转发到 build.sh）
            示例: ./deploy.sh build 1.2.5
                  ./deploy.sh build latest multi
  start   启动 OpenCode
  stop    停止服务
  restart 重启服务
  status  查看运行状态
  logs    查看实时日志
  update  重新构建并升级到最新版
  help    显示此帮助

部署步骤:
  1. ./deploy.sh init        # 初始化
  2. 编辑 .env（设置用户名/密码）
  3. ./deploy.sh build       # 构建镜像
  4. ./deploy.sh start       # 启动
  5. 配置外部 nginx 反代到 127.0.0.1:4096（自行处理 HTTPS/证书）
  6. 手机访问 https://<你的域名>

外部 nginx 反代示例（仅供参考）：
  location / {
      proxy_pass http://127.0.0.1:4096;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_read_timeout 600s;
      proxy_buffering off;
  }

EOF
}

# ============== 入口 ==============
case "${1:-help}" in
    init)   cmd_init ;;
    build)  shift; cmd_build "$@" ;;
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    restart) cmd_restart ;;
    status) cmd_status ;;
    logs)   cmd_logs ;;
    update) cmd_update ;;
    help|*) cmd_help ;;
esac
