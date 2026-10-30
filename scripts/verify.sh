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
    # --- v6.6 아침 브리핑: 톡방 4개에 하루 한 번만, 본문 형식 ---
    $PS -d ictc_verify -At -c "select ictc_save('0000','schedule','{\"id\":\"vb1\",\"title\":\"브리핑검증\",\"date\":\"2026-10-27\",\"start\":\"09:00\",\"tags\":[\"주요업무\"]}'::jsonb,'main')" >/dev/null 2>&1
    b1=$($PS -d ictc_verify -At -c "select ictc_chat_briefing('2026-10-27')" 2>&1); b2=$($PS -d ictc_verify -At -c "select ictc_chat_briefing('2026-10-27')" 2>&1)
    btxt=$($PS -d ictc_verify -At -c "select data->>'text' from ictc_items where id='brief-ictc-20261027'" 2>&1)
    { [ "$b1" = "4" ] && [ "$b2" = "0" ] && [[ "$btxt" == *"10월 27일(화) 아침 브리핑 · 지휘역량강화센터"* ]] && [[ "$btxt" == *"09:00 ★ 브리핑검증"* ]]; } && echo "  아침 브리핑 생성(4개 톡방·중복 없음·형식) ok" || { echo "  아침 브리핑 검사 실패: $b1 / $b2 / $btxt"; ok=0; }
    bnow=$($PS -d ictc_verify -At -c "select ictc_chat_briefing_now('1234')" 2>&1); bnow2=$($PS -d ictc_verify -At -c "select ictc_chat_briefing_now('1234')" 2>&1); bman=$($PS -d ictc_verify -At -c "select count(*) from ictc_items where id like 'brief-ictc-%-m%' and data->>'text' like '%수동 게시%'" 2>&1); { [ "$bnow" = "4" ] && [ "$bnow2" = "4" ] && [ "$bman" = "2" ]; } && echo "  브리핑 테스트(관리자, 매번 새 글·수동 게시 표시) ok" || { echo "  브리핑 테스트 실패: $bnow / $bnow2 / $bman"; ok=0; }
    nset=$($PS -d ictc_verify -At -c "select ictc_news_set('2026-10-27', '[{\"title\":\"아파트 화재 20명 대피\",\"press\":\"연합뉴스\",\"url\":\"https://example.com/a\"},{\"title\":\"소방관 순직 애도\",\"press\":\"KBS\",\"url\":\"https://example.com/b\"}]'::jsonb)" 2>&1)
    ntxt=$($PS -d ictc_verify -At -c "select data->>'text' from ictc_items where id='brief-ictc-20261027'" 2>&1)
    { [ "$nset" = "4" ] && [[ "$ntxt" == *"소방 뉴스"* ]] && [[ "$ntxt" == *" 1. 아파트 화재 20명 대피 (연합뉴스) https://example.com/a"* ]] && [[ "$ntxt" != *"내일 일정"* ]] && [[ "$ntxt" != *"기한 지남"* ]]; } && echo "  브리핑 뉴스 붙이기(오늘 글 4개 갱신·내일/업무 절 없음) ok" || { echo "  브리핑 뉴스 검사 실패: $nset / $ntxt"; ok=0; }
    nanon=$(psql -h $PGD -p 5499 -U anon -d ictc_verify -At -c "select * from ictc_news" 2>&1); [[ "$nanon" == *"permission denied"* ]] && echo "  뉴스 표 anon 차단 ok" || { echo "  뉴스 표가 anon 에 열려 있음: $nanon"; ok=0; }
    banon=$(psql -h $PGD -p 5499 -U anon -d ictc_verify -At -c "select ictc_chat_briefing('2026-10-27')" 2>&1); [[ "$banon" == *"permission denied"* ]] && echo "  브리핑 내부 함수 anon 거부 ok" || { echo "  브리핑 함수가 anon 에 열려 있음: $banon"; ok=0; }
    # --- v6.4 추가 검사 ---
    nosp=$($PS -d ictc_verify -At -c "select string_agg(p.proname, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'ictc\\_%' and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c where c like 'search_path=%extensions%')")
    [ -z "$nosp" ] && echo "  모든 함수 search_path=public, extensions ok" || { echo "  search_path 누락 함수: $nosp"; ok=0; }
    internal=$($PS -d ictc_verify -At -c "select bool_or(has_function_privilege('anon', p.oid, 'execute')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('ictc_fail_delay','ictc_check_pin','ictc_check_view_pin','ictc_user_check','ictc_require_view','ictc_require_edit','ictc_trash','ictc_chat_check','ictc_check_item')")
    [ "$internal" = "f" ] && echo "  내부 함수 anon 실행 거부 ok" || { echo "  내부 함수를 anon 이 실행할 수 있음: $internal"; ok=0; }
    big=$($PS -d ictc_verify -At -c "select ictc_save('0000','schedule', jsonb_build_object('id','big','title',repeat('x',70000)))" 2>&1); [[ "$big" == *ITEM_TOO_LARGE* ]] && echo "  64KB 초과 항목 거부 ok" || { echo "  큰 항목이 저장됨: $big"; ok=0; }
    nob=$($PS -d ictc_verify -At -c "select ictc_save('0000','schedule', '{\"id\":\"x1\",\"title\":\"t\"}'::jsonb, 'no-such-board')" 2>&1); [[ "$nob" == *BOARD_NOT_FOUND* ]] && echo "  없는 대시보드 저장 거부 ok" || { echo "  없는 대시보드에 저장됨: $nob"; ok=0; }
    $PS -d ictc_verify -q -c "select ictc_save('0000','schedule','{\"id\":\"s1\",\"title\":\"일정\",\"tags\":[\"주요업무\"]}'::jsonb); select ictc_save('0000','tasks','{\"id\":\"sch-s1\",\"title\":\"일정\",\"fromSchedule\":\"s1\"}'::jsonb); select ictc_delete('0000','schedule','s1');" >/dev/null 2>&1
    left=$($PS -d ictc_verify -At -c "select count(*) from ictc_items where id in ('s1','sch-s1')"); trashed=$($PS -d ictc_verify -At -c "select count(*) from ictc_deleted_list('1234') where id in ('s1','sch-s1')")
    [ "$left$trashed" = "02" ] && echo "  일정 삭제 → 연동 카드 함께 휴지통 ok" || { echo "  연동 카드 삭제 불일치: 남은 $left, 휴지통 $trashed"; ok=0; }
    seq=$($PS -d ictc_verify -At -c "select seq from ictc_deleted_list('1234','schedule') where id='s1' limit 1"); $PS -d ictc_verify -q -c "select ictc_restore('1234', $seq)" >/dev/null 2>&1
    back=$($PS -d ictc_verify -At -c "select count(*) from ictc_items where id in ('s1','sch-s1')"); [ "$back" = "2" ] && echo "  일정 복구 → 연동 카드 함께 복구 ok" || { echo "  복구 불일치: $back"; ok=0; }
    $PS -d ictc_verify -q -c "select ictc_chat_save('0000','ictc','5948','{\"id\":\"m1\",\"text\":\"원문\",\"name\":\"a\"}'::jsonb); select ictc_chat_save('0000','ictc','5948','{\"id\":\"m1\",\"deleted\":true,\"text\":\"\",\"name\":\"a\"}'::jsonb);" >/dev/null 2>&1
    ctr=$($PS -d ictc_verify -At -c "select data->>'text' from ictc_deleted_list('1234','chat','ictc') where id='m1'"); [ "$ctr" = "원문" ] && echo "  41망 삭제 글 원문 휴지통 보관 ok" || { echo "  41망 삭제 글이 휴지통에 없음: '$ctr'"; ok=0; }
    dup=$($PS -d ictc_verify -At -c "select ictc_replace('1234','tasks','[{\"id\":\"d1\",\"title\":\"a\"},{\"id\":\"d1\",\"title\":\"b\"}]'::jsonb)" 2>&1); [ -z "$dup" ] && echo "  JSON 가져오기 중복 id 허용(마지막 것) ok" || { echo "  중복 id 가져오기 실패: $dup"; ok=0; }
    echo "  함수 $fn 개, 2회 실행 완료"
    # --- v1(최초 커밋) → 현재 순서로 적용해 PIN·데이터가 보존되는지 ---
    if git cat-file -e e76564c:server/supabase.sql 2>/dev/null; then
      $PS -c "drop database if exists ictc_migrate" >/dev/null 2>&1; $PS -c "create database ictc_migrate" >/dev/null
      $PS -d ictc_migrate -c "create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions;" >/dev/null
      git show e76564c:server/supabase.sql | $PS -d ictc_migrate -v ON_ERROR_STOP=1 -f - >/dev/null 2>&1 || { echo "  v1 적용 실패"; ok=0; }
      $PS -d ictc_migrate -q -c "select ictc_set_pin('1234','9876'); select ictc_save('9876','schedule','{\"id\":\"old1\",\"title\":\"옛 일정\"}'::jsonb);" >/dev/null 2>&1
      $PS -d ictc_migrate -v ON_ERROR_STOP=1 -f server/supabase.sql >/tmp/verify_mig.log 2>&1 || { echo "  v1→현재 적용 실패:"; grep -v NOTICE /tmp/verify_mig.log | tail -3; ok=0; }
      kept=$($PS -d ictc_migrate -At -c "select (select value from ictc_settings where key='edit_pin') || '/' || (select count(*) from ictc_items where id='old1' and board='main') || '/' || (select data->>'title' from ictc_list('0000','schedule') limit 1)")
      [ "$kept" = "9876/1/옛 일정" ] && echo "  v1→현재 마이그레이션: 편집 PIN·데이터 보존 ok" || { echo "  마이그레이션 보존 실패: $kept"; ok=0; }
    fi
    su postgres -c "$PGBIN/pg_ctl -D $PGD/data stop >/dev/null 2>&1"
  else echo "  (PostgreSQL 없음, 건너뜀)"; fi
fi
if [[ " $* " != *" --no-zip "* ]]; then echo "== ZIP"; python3 -I server/build_zip.py | head -1 || ok=0; fi
[ $ok = 1 ] && echo "== 전체 통과" || { echo "== 실패 있음"; exit 1; }
