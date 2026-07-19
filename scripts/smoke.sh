#!/usr/bin/env bash
# 对已启动的全栈做最小 HTTP 冒烟（BFF 路径）
set -euo pipefail
WEB="${F2B_WEB_URL:-http://127.0.0.1:3000}"
SBX="${F2B_SANDBOX_URL:-http://127.0.0.1:8787}"

echo "health sandbox"
curl -sf "$SBX/healthz" | head -c 200; echo
echo "health web"
curl -sf -o /dev/null -w "web %{http_code}\n" "$WEB/"
echo "bff create"
CREATE=$(curl -sf -X POST "$WEB/api/sandboxes" \
  -H 'content-type: application/json' \
  -d '{"name":"infra-smoke","template":"base"}')
echo "$CREATE" | head -c 240; echo
ID=$(node -e "const j=JSON.parse(process.argv[1]); if(!j.sandbox?.id) process.exit(2); console.log(j.sandbox.id)" "$CREATE")
curl -sf -X POST "$WEB/api/sandboxes/$ID/commands" \
  -H 'content-type: application/json' \
  -d '{"cmd":"echo infra-ok"}' | head -c 200; echo
curl -sf -X DELETE "$WEB/api/sandboxes/$ID" >/dev/null
echo "INFRA_SMOKE_OK"
