#!/usr/bin/env bash
# 真 microVM 装栈前检查 + 装栈后验收编排（不 vendor Cube 内核）。
# 用法：
#   sudo bash scripts/cube-preflight.sh           # 主机探测
#   bash scripts/cube-preflight.sh --accept       # 要求 healthz.backend=cube 后跑验收
#   F2B_SANDBOX_URL=http://127.0.0.1:13287 bash scripts/cube-preflight.sh --accept
set -euo pipefail

MODE="preflight"
if [[ "${1:-}" == "--accept" ]]; then
  MODE="accept"
fi

SBX="${F2B_SANDBOX_URL:-http://127.0.0.1:13287}"
MIN_RAM_MB="${F2B_CUBE_MIN_RAM_MB:-7500}"

echo "== cube preflight / accept =="
echo "mode=$MODE host=$(hostname 2>/dev/null || echo unknown)"

fail=0
mem_ok=0

check_kvm() {
  if [[ -e /dev/kvm ]]; then
    echo "  kvm: /dev/kvm present"
    ls -l /dev/kvm 2>/dev/null || true
  else
    echo "  kvm: MISSING /dev/kvm"
    fail=1
  fi
  if [[ -r /proc/cpuinfo ]]; then
    n=$(grep -Ec '(vmx|svm)' /proc/cpuinfo || true)
    echo "  cpu virt flags count: $n"
  fi
  nested=$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || cat /sys/module/kvm_amd/parameters/nested 2>/dev/null || echo n/a)
  echo "  nested: $nested"
}

check_ram() {
  if command -v free >/dev/null 2>&1; then
    free -h || true
    # Mem total in MiB
    total_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    echo "  mem_total_mb=$total_mb (recommend >= $MIN_RAM_MB for real microVM accept)"
    if [[ "$total_mb" -ge "$MIN_RAM_MB" ]]; then
      mem_ok=1
    else
      echo "  WARN: RAM below recommend; 4G 机仅适合 0–1 guest 试验，不作容量承诺"
    fi
  else
    echo "  free: not available"
  fi
}

check_ports() {
  echo "  listeners (sample):"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | head -25 || true
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntp 2>/dev/null | head -25 || true
  fi
  echo "  note: CubeAPI 须仅 127.0.0.1；禁止公网暴露管理口"
}

check_healthz() {
  if ! curl -sf "$SBX/healthz" -o /tmp/f2b-cube-hz.json; then
    echo "  healthz: FAIL cannot reach $SBX/healthz"
    return 1
  fi
  echo -n "  healthz: "
  head -c 400 /tmp/f2b-cube-hz.json; echo
  backend=$(node -e "const j=require('/tmp/f2b-cube-hz.json'); process.stdout.write(String(j.backend||''))" 2>/dev/null || true)
  echo "  backend=$backend"
  if [[ "$backend" != "cube" ]]; then
    echo "  EXPECT backend=cube for --accept (got '$backend')"
    return 2
  fi
  return 0
}

if [[ "$MODE" == "preflight" ]]; then
  check_kvm
  check_ram
  check_ports
  if curl -sf "$SBX/healthz" -o /tmp/f2b-cube-hz.json 2>/dev/null; then
    echo -n "  sandbox healthz: "
    head -c 300 /tmp/f2b-cube-hz.json; echo
  else
    echo "  sandbox healthz: not reachable at $SBX (ok if not installed yet)"
  fi
  if [[ "$fail" -ne 0 ]]; then
    echo "CUBE_PREFLIGHT_FAIL (missing KVM)"
    exit 1
  fi
  if [[ "$mem_ok" -eq 1 ]]; then
    echo "CUBE_PREFLIGHT_OK mem_ok=1"
  else
    echo "CUBE_PREFLIGHT_OK mem_ok=0 (trial only)"
  fi
  echo "next: install Cube stack per upstream docs → set F2B_CUBE_* in sandbox.env → restart → $0 --accept"
  exit 0
fi

# --accept
if ! check_healthz; then
  echo "CUBE_ACCEPT_FAIL healthz"
  exit 1
fi

# Prefer in-tree smoke if f2b-sandbox is a sibling checkout
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX_DIR="${F2B_SANDBOX_DIR:-}"
if [[ -z "$SANDBOX_DIR" ]]; then
  if [[ -d "$ROOT/../f2b-sandbox" ]]; then
    SANDBOX_DIR="$ROOT/../f2b-sandbox"
  elif [[ -d /opt/f2b/f2b-sandbox ]]; then
    SANDBOX_DIR=/opt/f2b/f2b-sandbox
  fi
fi

if [[ -n "${SANDBOX_DIR:-}" && -f "$SANDBOX_DIR/package.json" ]]; then
  echo "  using sandbox dir: $SANDBOX_DIR"
  (
    cd "$SANDBOX_DIR"
    export F2B_SANDBOX_URL="$SBX"
    # 产品层 cube HTTP 路径（create/cmd/files/kill 等）
    if pnpm exec tsx scripts/smoke-cube-http.ts; then
      echo "  smoke-cube-http ok"
    else
      echo "CUBE_ACCEPT_FAIL smoke-cube-http"
      exit 1
    fi
  )
else
  echo "  WARN: f2b-sandbox checkout not found; run manually:"
  echo "    F2B_SANDBOX_URL=$SBX pnpm smoke:cube-http"
  exit 1
fi

echo "CUBE_ACCEPT_OK"
echo "记录：将能力矩阵真 Cube 行刷新到 f2b-docs；控制台徽章应显示 cube · BFF → sandbox"
