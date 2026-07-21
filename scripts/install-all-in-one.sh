#!/usr/bin/env bash
# 单节点 all-in-one：在 Linux 主机安装/更新 f2b-sandbox + f2b-web（Fake 默认）
# 用法（root）：
#   curl -fsSL ... | bash   # 或
#   ./scripts/install-all-in-one.sh
#
# 环境变量（可选）：
#   F2B_ROOT=/opt/f2b
#   F2B_GIT_BASE=https://github.com/f2b-dev
#   F2B_BRANCH=main
#   F2B_MAX_CONCURRENT_SANDBOXES=2
#   F2B_SANDBOX_BACKEND=fake
#   F2B_AUTH_MODE=off              # 仅新建 sandbox.env 时写入
#   F2B_AUTH_MODE_SET=api_key     # 更新已有 sandbox.env 的 F2B_AUTH_MODE
#   F2B_SANDBOX_HOST=127.0.0.1    # 建议生产/测试机绑定本机，不公网暴露 13287
#   F2B_ADMIN_TOKEN=…             # sandbox 管理令牌；同步写入 web 的 F2B_SANDBOX_ADMIN_TOKEN
#   F2B_SANDBOX_API_KEY=sk_live_… # BFF 访问上游产品 API（auth=api_key 时）
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请用 root 运行（写 /opt/f2b、systemd、/etc/f2b）" >&2
  exit 1
fi

F2B_ROOT="${F2B_ROOT:-/opt/f2b}"
F2B_GIT_BASE="${F2B_GIT_BASE:-https://github.com/f2b-dev}"
F2B_BRANCH="${F2B_BRANCH:-main}"
F2B_SANDBOX_BACKEND="${F2B_SANDBOX_BACKEND:-fake}"
F2B_AUTH_MODE="${F2B_AUTH_MODE:-off}"
F2B_MAX_CONCURRENT_SANDBOXES="${F2B_MAX_CONCURRENT_SANDBOXES:-}"

DATA_DIR="/var/lib/f2b/sandbox/data"
LOG_DIR="/var/log/f2b"
ENV_DIR="/etc/f2b"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1" >&2
    exit 1
  }
}

echo "==> 检查依赖"
need_cmd git
need_cmd curl
if ! command -v node >/dev/null 2>&1; then
  echo "需要 Node.js ≥ 22（node:sqlite）" >&2
  exit 1
fi
NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [[ "$NODE_MAJOR" -lt 22 ]]; then
  echo "Node 版本过低: $(node -v)（需要 ≥22）" >&2
  exit 1
fi
if ! command -v pnpm >/dev/null 2>&1; then
  echo "==> 启用 pnpm (corepack)"
  corepack enable
  corepack prepare pnpm@9.15.0 --activate
fi

mkdir -p "$F2B_ROOT" "$DATA_DIR" "$LOG_DIR/sandbox" "$LOG_DIR/web" "$ENV_DIR"
chmod 700 "$ENV_DIR"

clone_or_pull() {
  local name="$1"
  local dir="$F2B_ROOT/$name"
  if [[ -d "$dir/.git" ]]; then
    # 部署机：始终对齐 origin（shallow 易与本地历史分叉，ff-only 会挂）
    echo "==> sync $name -> origin/$F2B_BRANCH"
    git -C "$dir" fetch --depth 1 origin "$F2B_BRANCH"
    git -C "$dir" checkout -B "$F2B_BRANCH" "origin/$F2B_BRANCH"
    git -C "$dir" reset --hard "origin/$F2B_BRANCH"
    git -C "$dir" clean -fd
  else
    echo "==> clone $name"
    git clone --depth 1 --branch "$F2B_BRANCH" "$F2B_GIT_BASE/$name.git" "$dir"
  fi
}

for repo in f2b-spec f2b-sandbox f2b-web; do
  clone_or_pull "$repo"
done

# sandbox env
# 可选：调用方传入时 upsert 到已有 env
upsert_env() {
  local file="$1" key="$2" value="$3"
  [[ -z "$value" ]] && return 0
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >>"$file"
  fi
  echo "==> 更新 ${file}: ${key}"
}

if [[ ! -f "$ENV_DIR/sandbox.env" ]]; then
  cat >"$ENV_DIR/sandbox.env" <<EOF
PORT=13287
HOST=${F2B_SANDBOX_HOST:-0.0.0.0}
F2B_SANDBOX_BACKEND=${F2B_SANDBOX_BACKEND}
F2B_AUTH_MODE=${F2B_AUTH_MODE}
DATABASE_URL=file:${DATA_DIR}/f2b-sandbox.db
EOF
  if [[ -n "$F2B_MAX_CONCURRENT_SANDBOXES" ]]; then
    echo "F2B_MAX_CONCURRENT_SANDBOXES=${F2B_MAX_CONCURRENT_SANDBOXES}" >>"$ENV_DIR/sandbox.env"
  fi
  if [[ -n "${F2B_ADMIN_TOKEN:-}" ]]; then
    echo "F2B_ADMIN_TOKEN=${F2B_ADMIN_TOKEN}" >>"$ENV_DIR/sandbox.env"
  fi
  chmod 600 "$ENV_DIR/sandbox.env"
  echo "==> 写入 $ENV_DIR/sandbox.env"
else
  echo "==> 保留已有 $ENV_DIR/sandbox.env"
  # 迁移默认端口 8787→13287（项目专属）
  upsert_env "$ENV_DIR/sandbox.env" PORT "13287"
  upsert_env "$ENV_DIR/sandbox.env" F2B_MAX_CONCURRENT_SANDBOXES "${F2B_MAX_CONCURRENT_SANDBOXES:-}"
  upsert_env "$ENV_DIR/sandbox.env" F2B_AUTH_MODE "${F2B_AUTH_MODE_SET:-}"
  upsert_env "$ENV_DIR/sandbox.env" HOST "${F2B_SANDBOX_HOST:-}"
  upsert_env "$ENV_DIR/sandbox.env" F2B_ADMIN_TOKEN "${F2B_ADMIN_TOKEN:-}"
fi

if [[ ! -f "$ENV_DIR/web.env" ]]; then
  cat >"$ENV_DIR/web.env" <<EOF
PORT=13200
HOSTNAME=0.0.0.0
F2B_SANDBOX_URL=http://127.0.0.1:13287
EOF
  if [[ -n "${F2B_SANDBOX_API_KEY:-}" ]]; then
    echo "F2B_SANDBOX_API_KEY=${F2B_SANDBOX_API_KEY}" >>"$ENV_DIR/web.env"
  fi
  if [[ -n "${F2B_ADMIN_TOKEN:-}" ]]; then
    echo "F2B_SANDBOX_ADMIN_TOKEN=${F2B_ADMIN_TOKEN}" >>"$ENV_DIR/web.env"
  fi
  chmod 600 "$ENV_DIR/web.env"
  echo "==> 写入 $ENV_DIR/web.env"
else
  echo "==> 保留已有 $ENV_DIR/web.env"
  # 迁移默认端口 3000→13200，上游 8787→13287
  upsert_env "$ENV_DIR/web.env" PORT "13200"
  upsert_env "$ENV_DIR/web.env" F2B_SANDBOX_URL "http://127.0.0.1:13287"
  upsert_env "$ENV_DIR/web.env" F2B_SANDBOX_API_KEY "${F2B_SANDBOX_API_KEY:-}"
  if [[ -n "${F2B_ADMIN_TOKEN:-}" ]]; then
    upsert_env "$ENV_DIR/web.env" F2B_SANDBOX_ADMIN_TOKEN "$F2B_ADMIN_TOKEN"
  fi
fi

echo "==> pnpm install + build"
(cd "$F2B_ROOT/f2b-spec" && pnpm install --frozen-lockfile || pnpm install)
(cd "$F2B_ROOT/f2b-sandbox" && pnpm install --frozen-lockfile || pnpm install)
(cd "$F2B_ROOT/f2b-web" && pnpm install --frozen-lockfile || pnpm install)
# web 生产启动需 build
(cd "$F2B_ROOT/f2b-web" && \
  set -a && source "$ENV_DIR/web.env" && set +a && \
  pnpm --filter @f2b/web build)

echo "==> systemd units"
cat >/etc/systemd/system/f2b-sandbox.service <<EOF
[Unit]
Description=F2B Sandbox API (fake data plane)
After=network.target

[Service]
Type=simple
WorkingDirectory=${F2B_ROOT}/f2b-sandbox
EnvironmentFile=${ENV_DIR}/sandbox.env
ExecStart=$(command -v pnpm) start
Restart=on-failure
RestartSec=3
StandardOutput=append:${LOG_DIR}/sandbox/service.log
StandardError=append:${LOG_DIR}/sandbox/service.log

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/f2b-web.service <<EOF
[Unit]
Description=F2B Web console + BFF
After=network.target f2b-sandbox.service
Wants=f2b-sandbox.service

[Service]
Type=simple
WorkingDirectory=${F2B_ROOT}/f2b-web
EnvironmentFile=${ENV_DIR}/web.env
ExecStart=$(command -v pnpm) --filter @f2b/web start
Restart=on-failure
RestartSec=3
StandardOutput=append:${LOG_DIR}/web/service.log
StandardError=append:${LOG_DIR}/web/service.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable f2b-sandbox f2b-web
systemctl restart f2b-sandbox
systemctl restart f2b-web

echo "==> 健康检查"
ok_sandbox=0
ok_web=0
for i in $(seq 1 60); do
  if [[ "$ok_sandbox" -eq 0 ]] && curl -sf http://127.0.0.1:13287/healthz >/dev/null; then
    ok_sandbox=1
  fi
  if [[ "$ok_web" -eq 0 ]] && curl -sf -o /dev/null http://127.0.0.1:13200/; then
    ok_web=1
  fi
  if [[ "$ok_sandbox" -eq 1 && "$ok_web" -eq 1 ]]; then
    break
  fi
  sleep 1
done
curl -sS http://127.0.0.1:13287/healthz || true
echo
curl -sS -o /dev/null -w "web=%{http_code}\n" http://127.0.0.1:13200/ || true
if [[ "$ok_sandbox" -ne 1 || "$ok_web" -ne 1 ]]; then
  echo "WARN: 健康检查未在 60s 内全部就绪 (sandbox=$ok_sandbox web=$ok_web)" >&2
  systemctl --no-pager --full status f2b-sandbox f2b-web | sed -n '1,50p' || true
else
  systemctl --no-pager --full status f2b-sandbox f2b-web | sed -n '1,40p' || true
fi

echo ""
echo "INSTALL_OK"
echo "  控制台  http://<host>:13200"
echo "  沙箱    http://127.0.0.1:13287/healthz（建议 HOST=127.0.0.1 不公网暴露）"
echo "  约定    见 f2b-infra/docs/all-in-one.md"
echo "  测试机  见 f2b-infra/docs/hk-test-host.md"
