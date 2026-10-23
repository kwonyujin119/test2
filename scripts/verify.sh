#!/usr/bin/env bash
# 통합 검증: JS 문법 / Python 문법 / SQL(로컬 PostgreSQL) / ZIP 빌드
# 사용: bash scripts/verify.sh [--no-sql] [--no-zip]
set -u
cd "$(dirname "$0")/.."
ok=1
echo "== JS 문법"
node -e "const fs=require('fs');const s=fs.readFileSync('index.html','utf8');new Function(s.slice(s.lastIndexOf('<script>')+8,s.lastIndexOf('</script>')));console.log('  ok')" || ok=0
echo "== Python 문법"
python3 -I -c "import ast;[ast.parse(open(f,encoding='utf-8').read()) for f in ('server/ictc_server.py','server/build_zip.py')];print('  ok')" || ok=0
if [[ " $* " != *" --no-sql "* ]]; then
  echo "== SQL (로컬 PostgreSQL)"
  PGBIN=/usr/lib/postgresql/16/bin; PGD=/var/lib/postgresql/ictc_test
  if [ -x "$PGBIN/pg_ctl" ]; then
    if [ ! -d "$PGD/data" ]; then mkdir -p "$PGD" && chown postgres:postgres "$PGD" && su postgres -c "$PGBIN/initdb -D $PGD/data -U postgres --auth=trust -E UTF8 >/dev/null 2>&1"; fi
    su postgres -c "$PGBIN/pg_ctl -D $PGD/data -o '-p 5499 -k $PGD' -l $PGD/log start >/dev/null 2>&1"; sleep 2
    PS="psql -h $PGD -p 5499 -U postgres -q"
    $PS -c "create role anon nologin" >/dev/null 2>&1; $PS -c "create role authenticated nologin" >/dev/null 2>&1
    $PS -c "drop database if exists ictc_verify" >/dev/null 2>&1; $PS -c "create database ictc_verify" >/dev/null
    # Supabase 와 같은 구조: pgcrypto 를 extensions 스키마에 설치 (search_path 누락을 잡기 위함)
    $PS -d ictc_verify -c "create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions;" >/dev/null
    for i in 1 2; do $PS -d ictc_verify -v ON_ERROR_STOP=1 -f server/supabase.sql > /tmp/verify_sql.log 2>&1 || { echo "  실행 $i 실패:"; grep -v NOTICE /tmp/verify_sql.log | tail -5; ok=0; }; done
    $PS -c "alter role anon login" >/dev/null 2>&1
    denied=$(psql -h $PGD -p 5499 -U anon -d ictc_verify -At -c "select * from ictc_items" 2>&1 | grep -c "permission denied")
    fn=$($PS -d ictc_verify -At -c "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'ictc\_%'")
    [ "$denied" = "1" ] && echo "  anon 직접 조회 차단 ok" || { echo "  anon 직접 조회가 막히지 않음!"; ok=0; }
    chat=$($PS -d ictc_verify -At -c "select ictc_chat_join('0000','ictc','5948')" 2>&1); [ "$chat" = "지휘역량강화센터" ] && echo "  톡방 입장코드 ok" || { echo "  톡방 입장 실패: $chat"; ok=0; }
    bad=$($PS -d ictc_verify -At -c "select ictc_chat_join('0000','ictc','0000')" 2>&1); [[ "$bad" == *CHAT_CODE_INVALID* ]] && echo "  틀린 입장코드 거부 ok" || { echo "  틀린 입장코드가 통과됨: $bad"; ok=0; }
    reg=$($PS -d ictc_verify -At -c "select ictc_user_register('0000','9999','검증','1234')" 2>&1)
    [ "$reg" = "검증" ] && echo "  개인업무 등록(pgcrypto) ok" || { echo "  개인업무 등록 실패: $reg"; ok=0; }
    [ "$($PS -d ictc_verify -At -c "select ictc_user_login('9999','1234')" 2>&1)" = "검증" ] && echo "  개인업무 로그인 ok" || { echo "  개인업무 로그인 실패"; ok=0; }
    short=$($PS -d ictc_verify -At -c "select ictc_user_set_pin('9999','1234','12')" 2>&1); [[ "$short" == *PIN_TOO_SHORT* ]] && echo "  4자리 미만 비밀번호 거부 ok" || { echo "  4자리 미만 비밀번호가 허용됨: $short"; ok=0; }
    echo "  함수 $fn 개, 2회 실행 완료"
    su postgres -c "$PGBIN/pg_ctl -D $PGD/data stop >/dev/null 2>&1"
  else echo "  (PostgreSQL 없음, 건너뜀)"; fi
fi
if [[ " $* " != *" --no-zip "* ]]; then echo "== ZIP"; python3 -I server/build_zip.py | head -1 || ok=0; fi
[ $ok = 1 ] && echo "== 전체 통과" || { echo "== 실패 있음"; exit 1; }
