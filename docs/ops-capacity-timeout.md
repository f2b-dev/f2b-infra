# 香港测试机运维：容量 · 超时 · 保活

> 主机与端口见 [hk-test-host.md](./hk-test-host.md)；安装见 [all-in-one.md](./all-in-one.md)。  
> 容量分档原则见文档站 [architecture/capacity](https://github.com/f2b-dev/f2b-docs/blob/main/docs/architecture/capacity.md)。

本文只写 **单机 Fake all-in-one** 日常运维会碰到的三件事：并发硬顶、空闲超时回收、活动保活。

---

## 1. 一眼看状态

在**本机**（sandbox 仅 loopback）：

```bash
curl -sS http://127.0.0.1:13287/healthz | jq .
systemctl is-active f2b-sandbox f2b-web f2b-tunnel
```

关注字段：

| 字段 | 含义 |
|------|------|
| `backend` | 应为 `fake`（真 Cube 联调前勿对外宣称 microVM） |
| `auth` | 测试机常见 `off` 或 `api_key`；**不**回显密钥 |
| `capacity.active` / `max` / `available` | 并发占用 / 硬顶 / 剩余 |
| `reaper.enabled` / `intervalMs` | 超时回收是否开启及扫描间隔 |

控制台：`http://<host>:13200/console` 概览卡片「并发占用」与容量条（经 BFF `/api/health`）。

---

## 2. 并发硬顶 `F2B_MAX_CONCURRENT_SANDBOXES`

| 项 | 值（香港试验机当前约定） |
|----|--------------------------|
| 环境文件 | `/etc/f2b/sandbox.env` |
| 典型值 | `2`（4c/4G 试验档；Fake 功能用） |
| 生效 | 改 env 后 `systemctl restart f2b-sandbox` |
| 未设置或 ≤0 | **不限制**（开发默认；勿在公网试验机长期使用） |

占用槽状态：`provisioning` / `running` / `paused`（终态 killed/failed/succeeded 不占槽）。

创建超顶时 API 返回 **429** `CAPACITY_EXCEEDED`，`details: { active, max }`。

### 运维动作

```bash
# 看硬顶与占用
curl -sS http://127.0.0.1:13287/healthz | jq '.capacity, .maxConcurrentSandboxes'

# 列出活动沙箱并腾槽
curl -sS 'http://127.0.0.1:13287/v1/sandboxes?status=running,paused,provisioning' \
  | jq -r '.sandboxes[].id' \
  | while read -r id; do
      curl -sS -X DELETE "http://127.0.0.1:13287/v1/sandboxes/$id" >/dev/null
      echo "killed $id"
    done
```

提高硬顶前先对照 capacity 分档：试验机 Fake 可略放宽；**真 microVM 不得按 Fake 密度承诺**。

---

## 3. 超时回收 reaper

| 环境变量 | 默认 | 说明 |
|----------|------|------|
| `F2B_TIMEOUT_REAPER_MS` | `2000` | 扫表间隔（ms）；`≤0` 关闭 |
| 沙箱 `timeoutMs` | 创建/PATCH | 空闲窗口（1 ms–24 h）；`null` 取消 |

到期点 = `lastActiveAt`（缺省 `startedAt` / `createdAt`）+ `timeoutMs`。  
到期 `kill`，`error` 记 `timeout exceeded`，并写 lifetime 用量。

启动时 reaper **立即扫一次**，清理重启前遗留超时实例。

```bash
# reaper 是否开启
curl -sS http://127.0.0.1:13287/healthz | jq .reaper

# 日志
journalctl -u f2b-sandbox -n 80 --no-pager | grep reaper
```

临时关闭（仅排障，勿长期）：

```bash
# 在 /etc/f2b/sandbox.env
F2B_TIMEOUT_REAPER_MS=0
systemctl restart f2b-sandbox
```

---

## 4. 滑动空闲保活（keepalive）

- 命令（含 stream）、文件读/写/列/删/mkdir/rename **成功**后刷新 `lastActiveAt`。
- `PATCH` 设置非 null `timeoutMs` 时同步刷新 `lastActiveAt`（从现在重新计时）。
- **不会**因仅 GET 详情/列表而保活。

控制台详情页展示 `lastActiveAt` 与空闲倒计时文案；SDK/MCP 走同一套服务端逻辑。

验证思路：

1. 创建短 `timeoutMs`（如 8000）。
2. 到期前执行一次命令或文件读。
3. 观察未在原到期点被 reaper 杀掉；`GET` 详情 `lastActiveAt` 已更新。

---

## 5. 常用 env 一览（sandbox）

路径：`/etc/f2b/sandbox.env`（以 install 脚本为准）。

| 变量 | 作用 |
|------|------|
| `HOST` / `PORT` | 建议 `127.0.0.1` / `13287` |
| `F2B_SANDBOX_BACKEND` | `fake`（试验机默认） |
| `F2B_MAX_CONCURRENT_SANDBOXES` | 并发硬顶 |
| `F2B_TIMEOUT_REAPER_MS` | reaper 间隔 |
| 鉴权相关 | 见 all-in-one；**禁止**把管理密钥写进前端或日志 |

web 侧只需 `F2B_SANDBOX_URL=http://127.0.0.1:13287`（及 BFF 上游密钥若启用）。

---

## 6. 排障速查

| 现象 | 检查 |
|------|------|
| 创建 429 CAPACITY_EXCEEDED | healthz `capacity`；销毁空闲；或调硬顶 |
| 沙箱「突然没了」且 error=timeout | reaper 日志；`timeoutMs` / `lastActiveAt`；是否有活动刷新 |
| 概览无容量数字 | sandbox 是否可达；BFF `/api/health`；web 是否指向正确 `F2B_SANDBOX_URL` |
| 公网能打 13287 | **立即**改 `HOST=127.0.0.1` 并重启；UFW 勿放行数据面 |

更新代码后：

```bash
cd /opt/f2b/f2b-infra && git pull --ff-only && sudo ./scripts/install-all-in-one.sh
# 期望尾部 INSTALL_OK
```
