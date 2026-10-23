#!/usr/bin/env bash
# 세 저장 모드 브라우저 E2E. 사용: bash scripts/e2e.sh [preview|local|supabase|all]  (기본 all)
# 산출물: $OUT (기본 /tmp/ictc-e2e) 에 스크린샷
set -u
cd "$(dirname "$0")/.."
MODE=${1:-all}; OUT=${OUT:-/tmp/ictc-e2e}; mkdir -p "$OUT"; SITE=$OUT/site; rm -rf "$SITE" "$OUT/ddata"; mkdir -p "$SITE"
# 포트: PORT_BASE 를 주면 그 번호부터 4개를 씀(에이전트 둘이 동시에 돌릴 때 충돌 방지). 기본 preview 8767 · local 8081 · mock 8766 · mock site 8765
if [[ -n "${PORT_BASE:-}" ]]; then P_PREVIEW=$PORT_BASE; P_LOCAL=$((PORT_BASE+1)); P_MOCK=$((PORT_BASE+2)); P_MSITE=$((PORT_BASE+3)); else P_PREVIEW=8767; P_LOCAL=8081; P_MOCK=8766; P_MSITE=8765; fi
cp index.html "$SITE/"; cp -r data assets checklist "$SITE/"
export NODE_PATH=$(npm root -g); rc=0; pids=()
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT
run() { echo "== $1"; node scripts/e2e.js "$2" "$3" "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  FAILS:', d['fails'] or '없음'); print('  ERRORS:', d['errors'] or '없음')" || rc=1; }
if [[ $MODE == preview || $MODE == all ]]; then
  echo 'window.ICTC_CONFIG={supabaseUrl:"",supabaseAnonKey:""};' > "$SITE/config.js"
  python3 -m http.server "$P_PREVIEW" --directory "$SITE" >/dev/null 2>&1 & pids+=($!); sleep 1
  run preview "http://127.0.0.1:$P_PREVIEW/" preview
fi
if [[ $MODE == local || $MODE == all ]]; then
  (cd server && python3 ictc_server.py --port "$P_LOCAL" --host 127.0.0.1 --static "$SITE" --db "$OUT/ddata/ictc.db" --pin-file "$OUT/ddata/pin.txt" >"$OUT/local.log" 2>&1 &) ; sleep 1.5
  pids+=($(pgrep -f "ictc_server.py --port $P_LOCAL" | head -1))
  run local "http://127.0.0.1:$P_LOCAL/" shared
fi
if [[ $MODE == supabase || $MODE == all ]]; then
  echo 'window.ICTC_CONFIG={supabaseUrl:"http://localhost:'"$P_MOCK"'",supabaseAnonKey:"test-anon",pollSeconds:10};' > "$SITE/config.js"
  python3 -I scripts/mock_supabase.py server/supabase.sql "$P_MOCK" >"$OUT/mock.log" 2>&1 & pids+=($!)
  python3 -m http.server "$P_MSITE" --directory "$SITE" >/dev/null 2>&1 & pids+=($!); sleep 1.5
  run supabase-mock "http://localhost:$P_MSITE/" shared
fi
exit $rc
