#!/usr/bin/env bash
# 不使用 Docker：在宿主机并行启动 f2b-sandbox + f2b-web（需本机 Node 22+ / pnpm）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SBX="$ROOT/f2b-sandbox"
WEB="$ROOT/f2b-web"
SPEC="$ROOT/f2b-spec"

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
export F2B_SANDBOX_URL="${F2B_SANDBOX_URL:-http://127.0.0.1:8787}"

cleanup() {
  [[ -n "${SBX_PID:-}" ]] && kill "$SBX_PID" 2>/dev/null || true
  [[ -n "${WEB_PID:-}" ]] && kill "$WEB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> install (idempotent)"
(cd "$SPEC" && pnpm install)
(cd "$SBX" && pnpm install)
(cd "$WEB" && pnpm install)

echo "==> f2b-sandbox :8787"
(cd "$SBX" && pnpm start) &
SBX_PID=$!

for i in $(seq 1 40); do
  if curl -sf http://127.0.0.1:8787/healthz >/dev/null 2>&1; then
    echo "sandbox ready"
    break
  fi
  sleep 0.25
done

echo "==> f2b-web :3000  (F2B_SANDBOX_URL=$F2B_SANDBOX_URL)"
(cd "$WEB" && F2B_SANDBOX_URL="$F2B_SANDBOX_URL" pnpm dev) &
WEB_PID=$!

echo ""
echo "  官网/控制台  http://localhost:3000"
echo "  沙箱 API     http://localhost:8787/healthz"
echo "  Ctrl+C 停止"
echo ""
wait
