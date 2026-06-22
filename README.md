# OpenCode Docker 部署（本地构建版）

本地构建 [OpenCode](https://github.com/anomalyco/opencode) 镜像并部署。反代和 HTTPS 由你自己的外部 nginx 处理。

## 架构

```
手机 ─HTTPS→ 你的外部 nginx ─proxy→ 127.0.0.1:4096 → opencode 容器
```

- **opencode 容器**：仅监听 `127.0.0.1:4096`，公网不可达
- **反代/证书/域名**：由你的外部 nginx 自行配置（本仓库不包含）

## 目录结构

```
opencode-docker/
├── Dockerfile               # 本地构建用 Dockerfile（基于原项目）
├── docker-compose.yml        # 服务编排（仅 opencode 容器）
├── build.sh                  # 镜像构建脚本（支持指定版本/多架构）
├── deploy.sh                 # 一键部署脚本
├── .env.sample               # 环境变量模板
├── .env                      # 实际环境变量（自行创建，勿提交）
└── data/
    ├── share/                # opencode 共享数据（含 auth.json）
    ├── state/                # opencode 状态
    └── config/               # opencode 配置（opencode.json）
```

## 部署步骤

### 1. 上传到服务器

把整个 `opencode-docker/` 目录上传到服务器，例如 `/opt/opencode-docker/`。

### 2. 初始化

```bash
cd /opt/opencode-docker
chmod +x deploy.sh build.sh
./deploy.sh init
```

脚本会：
- 从 `.env.sample` 生成 `.env`，自动写入随机强密码
- 创建 `data/` 三个子目录

### 3. 编辑 .env

```bash
nano .env
# 修改 OPENCODE_SERVER_USERNAME，密码可保留自动生成的
chmod 600 .env
```

### 4. 构建镜像

```bash
# 构建最新版
./deploy.sh build

# 或指定版本
./deploy.sh build 1.2.5

# 多架构（需要 docker buildx）
./deploy.sh build latest multi

# 查看 npm 上可用版本
./deploy.sh build --list
```

### 5. 启动

```bash
./deploy.sh start
```

### 6. 配置外部 nginx 反代

在你的 nginx 配置中加一段（自行处理证书/HTTPS）：

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name opencode.example.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:4096;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # 透传客户端信息
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # LLM 响应可能较慢
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;

        # 流式输出
        proxy_buffering off;
    }
}
```

### 7. 手机访问

手机浏览器打开 `https://<你的域名>`，使用 `.env` 中的用户名密码登录。

## 常用命令

| 命令 | 作用 |
|---|---|
| `./deploy.sh init`          | 首次初始化 |
| `./deploy.sh build`         | 构建镜像（默认 latest） |
| `./deploy.sh build 1.2.5`   | 构建指定版本 |
| `./deploy.sh build --list`  | 查看 npm 可用版本 |
| `./deploy.sh start`         | 启动 |
| `./deploy.sh stop`          | 停止 |
| `./deploy.sh restart`       | 重启 |
| `./deploy.sh status`        | 查看状态 |
| `./deploy.sh logs`          | 查看实时日志 |
| `./deploy.sh update`        | 重新构建 latest 并升级 |

## LLM Provider 配置

### auth.json（登录凭证）

放到 `data/share/auth.json`：

```json
{
  "github-copilot": {
    "type": "oauth",
    "access": "",
    "refresh": "",
    "expires": 0
  }
}
```

### opencode.json（模型配置）

放到 `data/config/opencode.json`：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "github-copilot/gpt-5-mini",
  "provider": {
    "github-copilot": {
      "whitelist": ["gpt-5-mini", "gpt-4.1"]
    }
  }
}
```

## 安全清单

- [x] 4096 端口仅监听 `127.0.0.1`，公网不可达
- [x] `.env` 权限 600，自动生成强密码
- [x] 非 root 用户运行 opencode 容器
- [x] Dockerfile 安装后版本校验
- [ ] **你还需要做**：外部 nginx 强制 HTTPS、HSTS、SSH 加固、fail2ban

## 备份

```bash
tar -czf opencode-backup-$(date +%F).tar.gz data/
```

`data/share/auth.json` 含 LLM provider 凭证，注意保密。

## 故障排查

**容器起不来**：`docker compose logs opencode` 查看日志。

**502 Bad Gateway**：检查容器是否健康 `./deploy.sh status`，确认 4096 端口在监听 `ss -tlnp | grep 4096`。

**构建失败**：检查 docker 版本和磁盘空间，必要时 `docker system prune` 后重试。

## 许可

基于 [pilinux/opencode-docker](https://github.com/pilinux/opencode-docker)（MIT）改造。OpenCode 由 Anomaly 团队维护，本仓库不隶属官方。
