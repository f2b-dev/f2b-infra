# 香港测试机 runbook（Fake all-in-one）

> **固定远程试验床**（2026-07-21 确认）。规格属 capacity 表「试验 + 可选 KVM」档；**默认 Fake**，非企业容量样板。

| 项 | 值 |
|----|-----|
| 主机 | `156.238.244.3`（Electerm：香港服务器 15m 4R4G） |
| 接入 | 本机 Electerm MCP `http://127.0.0.1:30837` |
| OS | Debian 13 · kernel `6.12.x` · x86_64 |
| 规格 | 4 vCPU（Xeon 8272CL）/ **~3.8 GiB** RAM / **40G** 盘（约 33G 可用） |
| 虚拟化 | 本身为 KVM guest；**`/dev/kvm` 存在**，`kvm_intel` 已加载，**nested=Y** |
| 代码 | `/opt/f2b/{f2b-spec,f2b-sandbox,f2b-web,f2b-infra}` |
| 数据 | `/var/lib/f2b/sandbox/data` |
| 环境 | `/etc/f2b/sandbox.env` · `/etc/f2b/web.env` |
| 日志 | `/var/log/f2b/{sandbox,web,setup}.log` |
| 单元 | `f2b-sandbox.service` · `f2b-web.service` |

## 探测摘要（2026-07-21）

| 检查 | 结果 |
|------|------|
| `/dev/kvm` | `crw-rw---- root:kvm` |
| CPU 标志 vmx | 有（`egrep -c vmx` ≥ 1） |
| nested | `Y` |
| `systemd-detect-virt` | `kvm` |
| 控制面 | `f2b-sandbox` / `f2b-web` **active**；`backend=fake` |
| 健康 | `13287/healthz` ok · `13200` HTTP 200 |
| 并发硬顶 | `F2B_MAX_CONCURRENT_SANDBOXES=2`（healthz 回显 `maxConcurrentSandboxes`） |
| 监听目标 | `22`、`13200` 可对公网；**`13287` 应仅 `127.0.0.1`**（BFF 本机回环） |
| UFW | 至少 OpenSSH；生产勿放行 13287 |

## 端口

| 端口 | 服务 | 说明 |
|------|------|------|
| 13200 | f2b-web | 控制台 + BFF（对外入口） |
| 13287 | f2b-sandbox | `/v1`；**仅 127.0.0.1**（`HOST=127.0.0.1`） |
| 80 | 可选反代 / docker | 视本机容器而定 |

本机冒烟：

```bash
curl -sS http://127.0.0.1:13287/healthz
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:13200/
systemctl is-active f2b-sandbox f2b-web
```

## 常用

```bash
systemctl status f2b-sandbox f2b-web
systemctl restart f2b-sandbox f2b-web
journalctl -u f2b-sandbox -u f2b-web -n 50 --no-pager
# 或 tail -f /var/log/f2b/*.log
```

更新代码后（或本仓脚本，需 root）：

```bash
# 推荐：与 install 脚本同源
cd /opt/f2b/f2b-infra && git pull --ff-only && sudo ./scripts/install-all-in-one.sh

# 或手工
cd /opt/f2b
for r in f2b-spec f2b-sandbox f2b-web; do git -C $r pull --ff-only; done
cd f2b-spec && pnpm i --frozen-lockfile
cd ../f2b-sandbox && pnpm i --frozen-lockfile
cd ../f2b-web && pnpm i --frozen-lockfile && F2B_SANDBOX_URL=http://127.0.0.1:13287 pnpm --filter @f2b/web build
systemctl restart f2b-sandbox f2b-web
```

## 角色边界

| 做 | 不做 |
|----|------|
| 控制面 + **Fake** 公网/远程验收 | 企业「可承诺」并发样板（见 capacity 4c/4G 行） |
| 可选：nested KVM **单 guest 实验**（内存紧，随时 OOM） | 与客户业务混部 |
| systemd all-in-one 演练 | 把 `auth=off` + 公网 13287 当生产 |
| 真数据面联调前准备：`/dev/kvm` 探测 | 在 **未装 Cube 栈** 时把 healthz 写成已连 microVM |

真 microVM 步骤与验收清单见 **[cube-single-node.md](./cube-single-node.md)**（本机 4G 仅实验；推荐另开 ≥8G）。

## 安全（测试机）

最小加固（推荐当前默认）：

```bash
# 13287 只听本机；控制台仍走 :13200 BFF
sudo F2B_SANDBOX_HOST=127.0.0.1 F2B_MAX_CONCURRENT_SANDBOXES=2 \
  /opt/f2b/f2b-infra/scripts/install-all-in-one.sh
# 或手改 /etc/f2b/sandbox.env 的 HOST=127.0.0.1 后 systemctl restart f2b-sandbox
ss -lntp | grep 13287   # 应为 127.0.0.1:13287
```

进阶（SDK 公网直连 13287 时才需要；本机绑定后可不做）：

1. `F2B_ADMIN_TOKEN` 写入 sandbox + web  
2. `F2B_AUTH_MODE_SET=api_key`  
3. 用 admin 创建 `sk_live_*`，写入 web 的 `F2B_SANDBOX_API_KEY`（BFF 注入，浏览器不持有）  
4. 反代 + TLS 只暴露 443→13200  

- **勿当生产**；无 Cube 管理密钥写入 env（Fake only）。

## 相关

- 进程/端口/目录：[all-in-one.md](./all-in-one.md)
- **真 microVM 单节点**：[cube-single-node.md](./cube-single-node.md)
- **容量 / 超时 / 保活运维**：[ops-capacity-timeout.md](./ops-capacity-timeout.md)
- 容量分档：f2b-docs `architecture/capacity`
- 能力矩阵：f2b-docs `architecture/capability-matrix`
- 其它候选机（不推荐作测试床）：润纳农业、snsc-prod-基础2 — 业务负载 / 无可靠 KVM 试验空间
