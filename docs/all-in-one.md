# 单节点 All-in-one 部署约定

> **默认交付形态**：一台 Linux 云主机同时跑控制面 +（可选）数据面。  
> 适用于：灵境云自用起步、企业入门包。多节点扩容后置，不阻塞本约定。

本文只定 **进程清单、端口、目录、环境变量边界**。容量与模板红线见文档站 [单机容量与模板规格](https://github.com/f2b-dev/f2b-docs)（`architecture/capacity`）。

---

## 1. 拓扑

```text
                    ┌─────────────────────────────────────────────┐
  公网 / 内网        │              单台 Linux 主机                 │
  客户端 ──────────►│  [可选] 反代 :80/:443                         │
                    │       │                                      │
                    │       ▼                                      │
                    │  f2b-web :13200   (UI + BFF)                  │
                    │       │ F2B_SANDBOX_URL                      │
                    │       ▼                                      │
                    │  f2b-sandbox :13287  (产品 /v1 API)           │
                    │       │                                      │
                    │       ├─ Fake（无 KVM / 本地开发）              │
                    │       └─ CubeAPI（本机 loopback，仅服务端）     │
                    │              └─ Cubelet / Hypervisor / guest  │
                    │                   envd（按 sandbox 动态寻址）   │
                    └─────────────────────────────────────────────┘
```

| 模式 | 何时用 | 数据面 |
|------|--------|--------|
| **A. 开发 / CI / 低配演示** | 笔记本、无 KVM、**2–4G 试验机** | `F2B_SANDBOX_BACKEND=fake` |
| **B. 单机真数据面** | 一台带 KVM 的云主机（建议 **≥8 GB** 再对外承诺并发） | 本机 Cube 栈 + `F2B_CUBE_API_URL=http://127.0.0.1:<cube-api>` |
| **C. 企业入门** | 与 B 相同拓扑；**允许 4c/8G 低配**（并发 1–2）或 8c/16G 推荐档 | 同 B；公网仅 443→web，SDK 走 BFF 或仅内网 :13287；容量见 capacity 分档 |

**禁止**：浏览器或客户端 SDK 配置 `CUBE_*` / `envdAccessToken`；CubeAPI 不对公网暴露。

---

## 2. 进程清单

### 2.1 始终需要（控制面）

| 进程 / 服务名 | 职责 | 建议用户 | 依赖 |
|---------------|------|----------|------|
| **f2b-sandbox** | 产品沙箱 API、API Key hash、领域状态、Fake 或 Cube adapter | `f2b` 或容器用户 | 磁盘上的 SQLite（或后续 Postgres） |
| **f2b-web** | 官网、控制台、同源 BFF（`/api/*` → sandbox） | 同上 | 仅依赖可达的 `F2B_SANDBOX_URL` |

本地编排对应 compose 服务名：`sandbox`、`web`（见根目录 `docker-compose.yml`）。

### 2.2 真数据面时增加（与控制面同机）

| 组件（逻辑名） | 职责 | 暴露范围 |
|----------------|------|----------|
| **CubeAPI**（或等价控制 API） | 生命周期 `POST/GET/DELETE /sandboxes` | **仅** `127.0.0.1` 或 docker 内网；供 f2b-sandbox 调用 |
| **节点代理 / Cubelet 等** | 本机创建/销毁 microVM | 不对外 |
| **Hypervisor / 镜像服务** | KVM guest、模板 rootfs | 不对外 |
| **数据面入口 / Proxy**（若启用） | 将 `{port}-{sandboxId}.{domain}` 转到 guest | 默认仅本机或内网；**不要**让浏览器持 token 直连 |
| **guest envd** | 命令 Connect、文件 HTTP | 仅经 f2b-sandbox 服务端访问 |

具体二进制与上游安装步骤以数据面发行版文档为准；灵境云侧只保证 **HTTP 字段与 adapter**（见 f2b-sandbox `CubeSandboxBackend` / `EnvdClient`）。

### 2.3 默认不进 all-in-one 常驻

| 组件 | 说明 |
|------|------|
| f2b-mcp-gateway | stdio MCP，按需起 |
| f2b-tunnel | 预览隧道：默认 all-in-one 常驻本机 `:8790`；BFF `/api/tunnels` |
| 独立 Postgres | MVP 用 SQLite 卷即可；企业可外置后换 `DATABASE_URL` |
| 多节点调度 / 跨机迁移 | 非本阶段 |

---

## 3. 端口约定

### 3.1 灵境云固定端口（产品）

| 端口 | 协议 | 进程 | 公网 | 说明 |
|------|------|------|------|------|
| **13200** | HTTP | f2b-web | 开发直接暴露；生产建议只经 443 | 控制台 + BFF |
| **13287** | HTTP | f2b-sandbox | 可选：仅内网或经网关 | 产品 `/v1`、`/healthz` |
| **8790** | HTTP | f2b-tunnel | 默认仅本机；预览 URL 可另设 `F2B_TUNNEL_PUBLIC_BASE` | `/v1/tunnels`、`/t/{id}/` |
| **80 / 443** | HTTP(S) | 反代（nginx/caddy 等） | 生产推荐 | 反代到 13200；API 可同域 `/` 或子域 |

宿主机映射可用环境变量覆盖（compose）：

- `F2B_WEB_PORT`（默认 13200）
- `F2B_SANDBOX_PORT`（默认 13287）
- `F2B_TUNNEL_PORT` / `F2B_TUNNEL_URL`（默认 8790）

### 3.2 仅本机 / 内网（数据面）

| 用途 | 约定 | 说明 |
|------|------|------|
| CubeAPI | `F2B_CUBE_API_URL`，推荐 `http://127.0.0.1:<port>` | **禁止**写入浏览器与公开文档示例为公网管理地址 |
| mock CubeAPI（开发） | `18991` | `pnpm mock:cube` |
| mock envd（开发） | `18992` | 同上；`F2B_CUBE_ENVD_BASE_URL` |
| 生产 envd 逻辑端口 | 默认 **49983**（`F2B_CUBE_ENVD_PORT`） | 寻址 `{port}-{sandboxId}.{domain}`，非固定监听在宿主机单一端口 |

### 3.3 防火墙建议（单机生产）

| 放行 | 拒绝 / 不映射 |
|------|----------------|
| 443（或 80→跳转）→ web | CubeAPI 端口对 `0.0.0.0` |
| 若 SDK 直连：仅受信网段 → 13287 | 任意 `CUBE_*` 管理端口公网 |
| SSH 仅运维网段 | 数据库文件目录的匿名共享 |

`F2B_AUTH_MODE`：公网暴露 13287 时必须 `api_key` + `F2B_ADMIN_TOKEN`；纯 BFF 同机且 13287 不对公网时可用 `off`（仅本机 docker 网络）。

---

## 4. 目录约定

### 4.1 宿主机推荐布局（裸机 / systemd）

```text
/etc/f2b/
  env                     # 环境变量（权限 600；含 token 时勿世界可读）
  web.env                 # 可选拆分
  sandbox.env
  tunnel.env

/var/lib/f2b/
  sandbox/
    data/                 # SQLite：f2b-sandbox.db 等
  cube/                   # 数据面数据根（镜像、实例元数据；路径随上游安装）
  backups/                # 仅控制面备份（见下）

/var/log/f2b/
  web/
  sandbox/
  tunnel/
```

### 4.2 Docker Compose（当前仓库默认）

| 路径 / 卷 | 用途 |
|-----------|------|
| 命名卷 `sandbox-data` | 容器内 `/data` → `DATABASE_URL=file:/data/f2b-sandbox.db` |
| 构建上下文 | **父目录**（与 `f2b-infra` 同级的 `f2b-spec` / `f2b-sandbox` / `f2b-web`） |
| `f2b-infra/.env` | 端口与 `F2B_SANDBOX_BACKEND`（勿提交密钥） |

### 4.3 备份与不要备份

| 备份 | 不要当热备 |
|------|------------|
| `/var/lib/f2b/sandbox/data`（或 compose 卷） | 正在跑的 microVM 内存态 |
| `/etc/f2b/*.env`（加密保管） | envdAccessToken 进程内缓存 |
| 反代与 TLS 证书配置 | guest 临时文件系统（用完即焚） |

机器重装后：恢复控制面 DB + env → 再调数据面；**旧 guest 一律视为已销毁**，产品侧应对账清理。

---

## 5. 环境变量边界（all-in-one）

| 变量 | 落在 | 说明 |
|------|------|------|
| `F2B_SANDBOX_URL` | **仅 web** | 指向本机或 compose 服务 `http://sandbox:13287` |
| `F2B_SANDBOX_BACKEND` | sandbox | `fake` 强制 Fake；有 Cube URL 且非 fake 则走真数据面 |
| `F2B_CUBE_API_URL` / `F2B_CUBE_API_TOKEN` | **仅 sandbox** | 同机 loopback；兼容 `CUBE_API_*` |
| `F2B_CUBE_ENVD_*` | 仅 sandbox | domain / port / 可选 `ENVD_BASE_URL` |
| `F2B_AUTH_MODE` / `F2B_ADMIN_TOKEN` | sandbox | 见上节防火墙 |
| `F2B_MAX_CONCURRENT_SANDBOXES` | sandbox | 单机并发硬顶；对齐 capacity 分档；未设不限制 |
| `DATABASE_URL` | sandbox | 默认文件库路径 |

完整示例见本仓 [`.env.example`](../.env.example) 与 [f2b-sandbox `.env.example`](https://github.com/f2b-dev/f2b-sandbox)。

---

## 6. 健康检查与冒烟

```bash
# 控制面
curl -sf http://127.0.0.1:13287/healthz
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:13200/

# compose 已 up 时
./scripts/smoke.sh
```

真数据面另需：见 **[cube-single-node.md](./cube-single-node.md)**。在 **该 Linux 主机** 上配置 `F2B_CUBE_*` 后，用 f2b-sandbox 的 create → command → kill 验收（无 KVM 时用 `pnpm mock:cube` + `pnpm smoke:cube` 只验协议）。

---

## 7. 扩容时本约定如何演进（预留口子）

| 阶段 | 变化 | 不变 |
|------|------|------|
| 单机纵向 | 加 CPU/内存/磁盘；下调并发红线见 capacity 文档 | 端口角色、密钥边界 |
| 拆数据面 | Cube 迁到第二台；`F2B_CUBE_API_URL` 改内网 IP | 客户端仍只打 web/13287 |
| 多节点 | 上调度与多 Cubelet | 产品 `/v1` 与 SDK 不要求客户改代码 |

---

## 8. 相关

- 本地 Fake 双容器：[README](../README.md)、文档站 `architecture/compose`
- 控制面 ≠ 数据面：`architecture/planes`
- 容量红线：`architecture/capacity`
