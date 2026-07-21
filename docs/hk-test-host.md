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
| 控制面 | `f2b-sandbox` / `f2b-web` **active**；`backend=fake`，`auth=off` |
| 健康 | `8787/healthz` ok · `3000` HTTP 200 |
| 监听 | `22`、`80`（docker-proxy）、`3000`、`8787` |
| UFW | OpenSSH + 80；**8787/3000 当前亦在 0.0.0.0**（测试便利，非生产） |

## 端口

| 端口 | 服务 | 说明 |
|------|------|------|
| 3000 | f2b-web | 控制台 + BFF |
| 8787 | f2b-sandbox | `/v1`，当前 `F2B_AUTH_MODE=off`（测试） |
| 80 | 可选反代 / docker | 视本机容器而定 |

本机冒烟：

```bash
curl -sS http://127.0.0.1:8787/healthz
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
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
cd ../f2b-web && pnpm i --frozen-lockfile && F2B_SANDBOX_URL=http://127.0.0.1:8787 pnpm --filter @f2b/web build
systemctl restart f2b-sandbox f2b-web
```

## 角色边界

| 做 | 不做 |
|----|------|
| 控制面 + **Fake** 公网/远程验收 | 企业「可承诺」并发样板（见 capacity 4c/4G 行） |
| 可选：nested KVM **单 guest 实验**（内存紧，随时 OOM） | 与客户业务混部 |
| systemd all-in-one 演练 | 把 `auth=off` + 公网 8787 当生产 |

## 安全（测试机）

- 联调：`auth=off`，进程监听 `0.0.0.0`。  
- **勿当生产**；公网暴露时至少：`F2B_AUTH_MODE=api_key`、8787 仅本机/内网、反代 + TLS。  
- 无 Cube 管理密钥写入 env（Fake only）。

## 相关

- 进程/端口/目录：[all-in-one.md](./all-in-one.md)
- 容量分档：f2b-docs `architecture/capacity`
- 其它候选机（不推荐作测试床）：润纳农业、snsc-prod-基础2 — 业务负载 / 无可靠 KVM 试验空间
