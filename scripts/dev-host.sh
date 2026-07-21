#!/usr/bin/env bash
# 不使用 Docker：在宿主机并行启动 f2b-sandbox + f2b-web（需本机 Node 22+ / pnpm）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SBX="$ROOT/f2b-sandbox"
WEB="$ROOT/f2b-web"
SPEC="$ROOT/f2b-spec"

# 项目专属本地端口（可用环境变量覆盖）
F2B_SANDBOX_PORT="${F2B_SANDBOX_PORT:-13287}"
F2B_WEB_PORT="${F2B_WEB_PORT:-13200}"

for d in "$SPEC" "$SBX" "$WEB"; do
  if [[ ! -d "$d" ]]; then
    echo "缺少目录: $d（请与 f2b-infra 同级克隆）" >&2
    exit 1
  fi
done

if ! command -v pnpm >/dev/null; then
  echo "需要 pnpm（corepack enable && corepack prepare pnpm@9.15.0 --activate）" >&2
  exit 1
fi

export F2B_SANDBOX_BACKEND="${F2B_SANDBOX_BACKEND:-fake}"
export DATABASE_URL="${DATABASE_URL:-file:$SBX/data/f2b-sandbox.db}"
export PORT="$F2B_SANDBOX_PORT"
export F2B_SANDBOX_URL="${F2B_SANDBOX_URL:-http://127.0.0.1:${F2B_SANDBOX_PORT}}"

cleanup() {
  [[ -n "${SBX_PID:-}" ]] && kill "$SBX_PID" 2>/dev/null || true
  [[ -n "${WEB_PID:-}" ]] && kill "$WEB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> install (idempotent)"
(cd "$SPEC" && pnpm install)
(cd "$SBX" && pnpm install)
(cd "$WEB" && pnpm install)

echo "==> f2b-sandbox :${F2B_SANDBOX_PORT}"
(cd "$SBX" && PORT="$F2B_SANDBOX_PORT" pnpm start) &
SBX_PID=$!

for i in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:${F2B_SANDBOX_PORT}/healthz" >/dev/null 2>&1; then
    echo "sandbox ready"
    break
  fi
  sleep 0.25
done

echo "==> f2b-web :${F2B_WEB_PORT}  (F2B_SANDBOX_URL=$F2B_SANDBOX_URL)"
(cd "$WEB" && F2B_SANDBOX_URL="$F2B_SANDBOX_URL" PORT="$F2B_WEB_PORT" pnpm --filter @f2b/web exec next dev --port "$F2B_WEB_PORT") &
WEB_PID=$!

echo ""
echo "  官网/控制台  http://localhost:${F2B_WEB_PORT}"
echo "  沙箱 API     http://localhost:${F2B_SANDBOX_PORT}/healthz"
echo "  Ctrl+C 停止"
echo ""
wait
