# 本地构建 OpenCode 镜像
# 基础镜像：node:24.15.0-bookworm
# 安装 opencode-ai 全局包，非 root 用户运行
# 支持 multi-arch：linux/amd64, linux/arm64
#
# 构建参数：
#   OPENCODE_VERSION: opencode-ai npm 包版本（默认 latest）
#
# 构建示例：
#   docker build -t opencode:local .
#   docker build --build-arg OPENCODE_VERSION=1.2.5 -t opencode:1.2.5-local .
#   docker buildx build --platform linux/amd64,linux/arm64 -t opencode:multi .

FROM node:24.15.0-bookworm

ARG OPENCODE_VERSION=latest

# set working directory
WORKDIR /app

# check architecture
RUN uname -m

# install opencode globally
# 安装后校验实际版本与预期版本一致，避免静默错版
RUN npm i -g "opencode-ai@${OPENCODE_VERSION}" && \
  installed_version_raw="$(opencode --version)" && \
  installed_version="${installed_version_raw#v}" && \
  echo "Installed opencode version: ${installed_version}" && \
  if [ "${OPENCODE_VERSION}" != "latest" ] && [ "${installed_version}" != "${OPENCODE_VERSION}" ]; then \
    echo "Expected opencode version ${OPENCODE_VERSION}, got ${installed_version}" >&2; \
    exit 1; \
  fi

# non-root user (recommended)
RUN adduser --disabled-password opencode

# create necessary directories and set permissions
RUN mkdir -p /home/opencode/.local/share/opencode/ && \
  mkdir -p /home/opencode/.local/state/opencode && \
  mkdir -p /home/opencode/.config/opencode/ && \
  chown -R opencode:opencode /home/opencode

# switch to non-root user
USER opencode

# 默认启动命令（docker-compose 会覆盖）
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
