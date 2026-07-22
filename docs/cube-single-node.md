# 真 microVM 单节点（Cube 数据面）联调 runbook

> **阶段 D**。控制面仍是 f2b-sandbox `/v1`；数据面从 Fake 切到 **本机 loopback 上的 CubeAPI + guest envd**。  
> **浏览器 / SDK 永不配置** `F2B_CUBE_*` / `CUBE_*` / `envdAccessToken`。

## 1. 主机选型

| 角色 | 规格建议 | 说明 |
|------|----------|------|
| **协议联调** | 任意（含本机） | `pnpm mock:cube` + `pnpm smoke:cube`，**不**起真 KVM |
| **nested 实验** | 香港测试机 `156.238.244.3`：4c / **~4G** / `/dev/kvm` nested=Y | **仅 0–1 guest**；易 OOM；**不**作容量承诺 |
| **单节点联调推荐** | ≥ **8G RAM**、SSD、x86_64 Linux + KVM | capacity「开发联调 / 企业入门」 |
| **对外小规模** | ≥ 8c / 16G | 见 f2b-docs `architecture/capacity` |

**已选定试验床（2026-07-22）**：香港机具备 KVM 设备与 nested，**当前仍 `backend=fake`**；真 Cube 二进制/栈 **未部署**。升配或另开 ≥8G 节点后再切生产数据面。

验收前探测（推荐脚本，等价于下列手工命令）：

```bash
# 在目标 Linux 主机
bash /path/to/f2b-infra/scripts/cube-preflight.sh
# → CUBE_PREFLIGHT_OK mem_ok=0|1
```

手工等价：

```bash
ls -l /dev/kvm
egrep -c '(vmx|svm)' /proc/cpuinfo
cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || true
free -h
# 应无公网监听的 Cube 管理端口
ss -lntp | head
```

## 2. 数据面栈（运维安装）

上游发行版名称因版本而异；灵境云只约定 **HTTP 契约**：

| 组件 | 职责 | 绑定 |
|------|------|------|
| CubeAPI（或等价） | `POST/GET/DELETE /sandboxes` 等生命周期 | **`127.0.0.1` only** |
| 节点代理 / Cubelet 等 | 创建/销毁 microVM | 不对外 |
| Hypervisor + 模板镜像 | KVM guest | 不对外 |
| guest **envd** | 命令 Connect、文件 HTTP | 仅 f2b-sandbox 服务端访问 |

安装步骤以 **数据面发行版官方文档** 为准（本仓不 vendor 内核）。装完后本机应能：

```bash
curl -sS -H "X-API-Key: $CUBE_TOKEN" http://127.0.0.1:<cube-port>/health
# 或发行版等价健康检查
```

## 3. 接入 f2b-sandbox

编辑 **仅服务端** env（如 `/etc/f2b/sandbox.env`），**不要**写进 web 的公开示例或前端：

```bash
# 去掉强制 fake；或显式
# F2B_SANDBOX_BACKEND=cube   # 可选；有 URL 且非 fake 即走 Cube

F2B_CUBE_API_URL=http://127.0.0.1:<cube-port>
F2B_CUBE_API_TOKEN=<服务端密钥>

# 可选
# F2B_CUBE_SANDBOX_DOMAIN=...
# F2B_CUBE_ENVD_PORT=49983
# F2B_CUBE_ENVD_BASE_URL=...   # 仅 mock/联调固定 envd 时

# 真 microVM 密度绝不可照抄 Fake
F2B_MAX_CONCURRENT_SANDBOXES=1   # 4G 机建议 1；8G 起再评估 1–2
```

```bash
systemctl restart f2b-sandbox
curl -sS http://127.0.0.1:13287/healthz
# 期望："backend":"cube"（或实现回报的 kind）；绝非在未配置时写死「已连集群」
```

解析逻辑见 f2b-sandbox `createSandboxBackend()`：`F2B_SANDBOX_BACKEND=fake` **强制** Fake；否则有 `F2B_CUBE_API_URL` / `CUBE_API_URL` 才实例化 `CubeSandboxBackend`。

## 4. 验收清单（真数据面）

在 **该 Linux 主机** 上（或经本机 13287）：

**一键（推荐）**：装栈并配置 `F2B_CUBE_*`、确认 `healthz.backend=cube` 后：

```bash
# 本机 13287 或指定 URL；需同级或 /opt/f2b 下有 f2b-sandbox checkout
F2B_SANDBOX_URL=http://127.0.0.1:13287 bash scripts/cube-preflight.sh --accept
# → CUBE_ACCEPT_OK（内部调 f2b-sandbox smoke:cube-http）
```

**手工清单**（`--accept` 未覆盖的项仍建议点验）：

| 步骤 | 期望 |
|------|------|
| `GET /healthz` | `backend` 反映真实 kind；`capacity` 硬顶合理 |
| create | `201`，`sandbox.backend` 非 `fake`（若实现透传） |
| `POST .../commands` | stdout/stderr/exitCode |
| `POST .../commands/stream` | SSE 事件 |
| 文件 utf8 读写 | 一致 |
| 文件 base64 读写 | 字节一致 |
| mkdir / rename / delete | 与 fake 语义对齐或记入差异表 |
| pause / resume | **视集群**；不支持则明确 4xx/错误码，勿假成功 |
| kill | 终态 + 用量 lifetime 记账 |
| timeout reaper | 短 `timeoutMs` 到期回收 |
| 并发硬顶 | 超限 `CAPACITY_EXCEEDED` |

协议-only（无真 KVM；**不**等于真 microVM 验收）：

```bash
cd f2b-sandbox
pnpm mock:cube &    # CubeAPI(:18991) + envd(:18992)
# A) adapter 直连
F2B_CUBE_API_URL=http://127.0.0.1:18991 \
  F2B_CUBE_ENVD_BASE_URL=http://127.0.0.1:18992 \
  F2B_CUBE_API_TOKEN=mock \
  pnpm smoke:cube
# → SMOKE_CUBE_OK

# B) 产品 HTTP /v1（backend=cube）
F2B_AUTH_MODE=off HOST=127.0.0.1 PORT=19791 \
  DATABASE_URL=file:./data/smoke-cube-http.db \
  F2B_CUBE_API_URL=http://127.0.0.1:18991 \
  F2B_CUBE_ENVD_BASE_URL=http://127.0.0.1:18992 \
  F2B_CUBE_API_TOKEN=mock \
  pnpm exec tsx src/server.ts &
# healthz 须 backend=cube
F2B_SANDBOX_URL=http://127.0.0.1:19791 pnpm smoke:cube-http
# → SMOKE_CUBE_HTTP_OK
# 契约 CI（ci:contract）已含 A+B
```

## 5. 诚实展示（产品）

| 表面 | 要求 |
|------|------|
| `GET /healthz` → `backend` | 真实 kind |
| 控制台顶栏 / 概览 | 展示 health 的 backend，**禁止**写死「已连真集群」 |
| 官网 / pricing | 不承诺未部署的 microVM 密度 |
| 文档 | Fake vs 真数据面 **能力矩阵**（f2b-docs） |

## 6. 与 Fake 的常见差异（填矩阵时）

| 能力 | Fake | 真 microVM（预期） |
|------|------|-------------------|
| 创建延迟 | 近瞬时 | 秒级（镜像/冷启动） |
| pause/resume | 支持 | **视发行版** |
| 命令超时 | fake 约 exit 124 | 视 envd |
| 文件/路径 | 内存 FS 语义 | guest 真实 FS |
| 并发密度 | 受 `F2B_MAX_*` 与内存 | **另受 KVM/内存/磁盘** |
| 网络 | 逻辑开关 | 真实隔离策略 |

## 7. 相关

- 香港机 Fake 运维：[hk-test-host.md](./hk-test-host.md)
- 进程/端口/密钥边界：[all-in-one.md](./all-in-one.md)
- 容量红线：f2b-docs `architecture/capacity`
- 能力矩阵：f2b-docs `architecture/capability-matrix`
- 控制面 ≠ 数据面：f2b-docs `architecture/planes`
