# f2b-infra

灵境云 **部署与本地全栈编排**（无业务逻辑）。

## 目录约定

与本仓**同级**克隆：

```text
revocloud/   # 或任意工作区父目录
  f2b-infra/     ← 本仓
  f2b-spec/
  f2b-sandbox/
  f2b-web/
  f2b-sdk-js/    # 可选，SDK 不进 compose
```

## 方式 A：Docker Compose（推荐联调镜像）

构建上下文为**父目录**（需同级 `f2b-spec` / `f2b-sandbox` / `f2b-web`）。建议复制忽略规则：

```bash
cd f2b-infra
cp parent.dockerignore ../.dockerignore   # 首次
cp .env.example .env                     # 可选
docker compose up --build
```

| 服务 | 地址 |
|------|------|
| 官网 / 控制台 | http://localhost:13200 |
| 沙箱 API | http://localhost:13287/healthz |

BFF 容器内通过 `F2B_SANDBOX_URL=http://sandbox:13287` 访问沙箱服务。  
数据卷：`sandbox-data` → SQLite。

冒烟（compose 已 up）：

```bash
./scripts/smoke.sh
```

停止：

```bash
docker compose down
```

## 方式 B：宿主机双进程（不构建镜像）

需 Node **≥ 22**（`node:sqlite`）与 pnpm：

```bash
./scripts/dev-host.sh
```

同样打开 :13200 / :13287。Ctrl+C 结束两个进程。

## 方式 C：Linux 单机 systemd 安装（Fake 默认）

在一台 Linux 上克隆/更新代码、写 `/etc/f2b/*.env`、安装 unit：

```bash
# 需 root、Node ≥ 22、git、curl
sudo F2B_MAX_CONCURRENT_SANDBOXES=2 ./scripts/install-all-in-one.sh
```

详情：[docs/all-in-one.md](./docs/all-in-one.md)、试验床 [docs/hk-test-host.md](./docs/hk-test-host.md)。

## 环境变量

见 [`.env.example`](./.env.example)。**勿提交**真实 `F2B_CUBE_API_TOKEN` 等密钥。

## 单节点 All-in-one（默认生产形态）

一台机同时跑 **web + sandbox**（及可选本机数据面）。进程清单、端口、目录、防火墙与扩容口子：

- **[docs/all-in-one.md](./docs/all-in-one.md)**

容量与默认模板承诺（并发、规格分档，**含低配入门**）：见文档站 **单机容量与模板**（f2b-docs `architecture/capacity`）。  
固定远程试验床（香港 Fake）：[docs/hk-test-host.md](./docs/hk-test-host.md)。  
真 microVM 单节点联调（KVM + 服务端 `F2B_CUBE_*`）：[docs/cube-single-node.md](./docs/cube-single-node.md)。

## 非目标

- 不写沙箱/控制台业务代码  
- 1.0 前不做复杂多集群 Helm 全集；**默认单节点** + compose 本地优先  
- npm 发布与生产密钥托管不在本仓

## 相关

- https://github.com/f2b-dev/f2b-sandbox  
- https://github.com/f2b-dev/f2b-web  
- https://github.com/f2b-dev/f2b-spec  

Apache-2.0

### Cube 装栈

```bash
bash scripts/cube-preflight.sh          # 预检
# 装上游 Cube 栈并配置 F2B_CUBE_* 后：
bash scripts/cube-preflight.sh --accept
```

详见 [docs/cube-single-node.md](./docs/cube-single-node.md)。
