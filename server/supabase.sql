-- ============================================================
-- SAIL:41 (지휘역량강화센터 일정·업무 보드) - Supabase 설정 (v6.20: 브리핑 공유 이미지 경로 · v6.19: 해외 −15 · v6.18: 지역 −8·무피해 −3·해프닝 −10·칼럼 −6 · v6.17: 해프닝 기사 감점 · v6.16: 인천 사건·시 정책만 최우선, 사망 가점 · v6.15: 뉴스 창 24시간·지역/전국 가중 · v6.14: 뉴스 5개·인천 최우선 · v6.13: 뉴스 수집을 DB 안에서(pg_net) · v6.12: 브리핑에 소방 뉴스 3개 · 내일·업무 절 삭제 · v6.11: 브리핑 평일 07:00 · v6.10: 관리자 브리핑 테스트는 매번 새 글 · v6.9: 브리핑 내일 일정은 건수만 · v6.8: 브리핑 목록에서 기한 지난 업무 제외 · v6.7: 브리핑 지금 올리기(관리자) · v6.6: 평일 08:00 아침 브리핑(pg_cron) · v6.5: 일정·업무 사진 첨부 경로 items/ 허용 · v6.4: 입력 크기 제한 · 일정↔연동카드 삭제·복구 일관성 · 41망 삭제 글 휴지통 · v6.3: 첨부 100MB · v6: 부서별 톡방 + 입장코드)
-- Supabase 대시보드 → SQL Editor → New query 에 전체를 붙여넣고 Run.
-- 여러 번 실행해도 안전합니다. 기존 데이터와 이미 설정한 PIN은 유지됩니다.
--
-- ★ 처음 설치할 때만 아래 두 PIN을 바꾸세요 (이미 설치된 경우 무시됨):
--    edit_pin : 편집 PIN (대시보드 관리, 사용자 관리, JSON 가져오기 등 관리 작업)
--    view_pin : 조회 PIN (링크를 여는 직원이 입력). 조회와 일정·주요업무 추가·수정·삭제 가능. '' 로 두면 누구나.
-- ============================================================
-- Supabase 는 pgcrypto 를 extensions 스키마에 두므로 모든 함수의 search_path 에 extensions 를 포함한다.
-- (로컬 PostgreSQL 처럼 extensions 스키마가 없으면 무시된다)
create extension if not exists pgcrypto;

-- 공용 항목 (일정·주요업무) + 개인업무
create table if not exists public.ictc_items (
  id          text primary key,
  kind        text not null,
  data        jsonb not null,
  updated_at  timestamptz not null default now()
);
alter table public.ictc_items add column if not exists board text not null default 'main';
alter table public.ictc_items drop constraint if exists ictc_items_kind_check;
alter table public.ictc_items add constraint ictc_items_kind_check check (kind in ('schedule', 'tasks', 'personal', 'chat'));
drop index if exists public.ictc_items_kind_board_idx;
create index if not exists ictc_items_kind_board_updated_idx on public.ictc_items (kind, board, updated_at desc);


-- 삭제 항목 보관(휴지통). 조회 PIN 으로 누구나 삭제할 수 있으므로 지운 항목의 사본을 30일 보관한다.
-- 삭제·JSON 가져오기(replace)·대시보드 삭제·개인업무 삭제 때 자동으로 쌓이고, 삭제가 일어날 때마다 30일 지난 행을 정리한다(cron 불필요).
-- 복구: select * from ictc_deleted_list('편집PIN');  →  select ictc_restore('편집PIN', seq);
create table if not exists public.ictc_items_deleted (
  seq         bigserial primary key,
  id          text not null,
  kind        text not null,
  board       text not null,
  data        jsonb not null,
  updated_at  timestamptz not null,
  deleted_at  timestamptz not null default now(),
  reason      text not null default 'delete'
);
create index if not exists ictc_items_deleted_deleted_at_idx on public.ictc_items_deleted (deleted_at);
create index if not exists ictc_items_deleted_id_idx on public.ictc_items_deleted (id);   -- 복구 때 연동 짝(일정 ↔ sch- 카드) 찾기

-- 대시보드 목록
create table if not exists public.ictc_boards (
  id          text primary key,
  name        text not null,
  created_at  timestamptz not null default now()
);
insert into public.ictc_boards (id, name) values ('main', '지휘역량강화센터') on conflict (id) do nothing;

-- 개인업무 사용자 (행정전화번호 뒤 4자리 = id, 이름 = 확인값)
create table if not exists public.ictc_users (
  id          text primary key,
  name        text not null,
  pin_hash    text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.ictc_settings (
  key   text primary key,
  value text not null
);
insert into public.ictc_settings (key, value) values ('edit_pin', '1234'), ('view_pin', '0000')
on conflict (key) do nothing;

-- 테이블 직접 접근 차단 (정책 없음 → 함수로만 접근)
alter table public.ictc_items    enable row level security;
alter table public.ictc_settings enable row level security;
alter table public.ictc_boards   enable row level security;
alter table public.ictc_users    enable row level security;
alter table public.ictc_items_deleted enable row level security;
drop policy if exists "ictc public read" on public.ictc_items;

-- 이전 버전 함수 정리 (시그니처 변경)
drop function if exists public.ictc_list(text, text);
drop function if exists public.ictc_save(text, text, jsonb);
drop function if exists public.ictc_delete(text, text, text);
drop function if exists public.ictc_replace(text, text, jsonb);

-- ---------- PIN 검증 ----------
create or replace function public.ictc_check_pin(p_pin text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select exists (select 1 from public.ictc_settings where key = 'edit_pin' and value = coalesce(p_pin, ''));
$$;
create or replace function public.ictc_check_view_pin(p_pin text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select coalesce((select value from public.ictc_settings where key = 'view_pin'), '') = ''
      or exists (select 1 from public.ictc_settings where key in ('view_pin', 'edit_pin') and value = coalesce(p_pin, ''));
$$;
-- PIN 틀릴 때마다 0.8초 지연 (무차별 대입 완화). 함수 안의 raise 는 트랜잭션을 롤백하므로
-- 실패 횟수를 테이블에 남기는 방식은 Supabase(자율 트랜잭션 없음)에서 동작하지 않는다. 지연은 롤백과 무관하게 적용된다.
create or replace function public.ictc_fail_delay()
returns void language sql security definer set search_path = public, extensions as $$ select pg_sleep(0.8); $$;

create or replace function public.ictc_require_view(p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(p_pin, '') = '' and coalesce((select value from public.ictc_settings where key = 'view_pin'), '') <> '' then
    raise exception 'VIEW_PIN_REQUIRED';
  end if;
  if not public.ictc_check_view_pin(p_pin) then
    perform public.ictc_fail_delay();
    raise exception 'VIEW_PIN_INVALID';
  end if;
end $$;
create or replace function public.ictc_require_edit(p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.ictc_check_pin(p_pin) then
    perform public.ictc_fail_delay();
    raise exception 'PIN_INVALID';
  end if;
end $$;

-- ---------- 항목 검사 (내부 전용) ----------
-- 화면은 제목 100자·메모 500자·상세 1000자·톡방 글 600자·첨부 10개로 제한하지만 서버도 한 행 64KB·id 100자를 넘기지 않게 막는다.
create or replace function public.ictc_check_item(p_item jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or coalesce(p_item->>'id', '') = '' then raise exception 'ID_REQUIRED'; end if;
  if length(p_item->>'id') > 100 or pg_column_size(p_item) > 65536 then raise exception 'ITEM_TOO_LARGE'; end if;
end $$;

-- ---------- 삭제 전 사본 보관 (내부 전용) ----------
-- p_id 가 null 이면 kind·board 전체. 30일 지난 보관 행은 이때 함께 정리한다.
create or replace function public.ictc_trash(p_kind text, p_board text, p_id text, p_reason text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.ictc_items_deleted (id, kind, board, data, updated_at, reason)
  select i.id, i.kind, i.board, i.data, i.updated_at, coalesce(p_reason, 'delete') from public.ictc_items i
   where i.kind = p_kind and i.board = p_board and (p_id is null or i.id = p_id);
  delete from public.ictc_items_deleted where deleted_at < now() - interval '30 days';
end $$;

-- ---------- 공용 항목 ----------
create or replace function public.ictc_list(p_pin text, p_kind text, p_board text default 'main')
returns table (data jsonb, updated_at timestamptz) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;   -- chat 은 ictc_chat_* (입장코드) 로만
  return query select i.data, i.updated_at from public.ictc_items i
    where i.kind = p_kind and i.board = coalesce(p_board, 'main') order by i.updated_at desc;
end $$;

-- 일정·주요업무의 추가·수정·삭제는 조회 PIN 을 아는 직원 누구나 가능 (편집 PIN 은 관리 작업 전용)
create or replace function public.ictc_save(p_pin text, p_kind text, p_item jsonb, p_board text default 'main')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;
  perform public.ictc_check_item(p_item);
  if not exists (select 1 from public.ictc_boards where id = coalesce(p_board, 'main')) then raise exception 'BOARD_NOT_FOUND'; end if;   -- 지워진 대시보드에 보이지 않는 행이 쌓이지 않게
  insert into public.ictc_items (id, kind, board, data, updated_at)
  values (p_item->>'id', p_kind, coalesce(p_board, 'main'), p_item, now())
  on conflict (id) do update set data = excluded.data, kind = excluded.kind, board = excluded.board, updated_at = now()
  where public.ictc_items.kind in ('schedule', 'tasks');   -- 같은 id 의 개인업무·톡방 행은 덮어쓰지 않음
end $$;

create or replace function public.ictc_delete(p_pin text, p_kind text, p_id text, p_board text default 'main')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;
  if coalesce(p_id, '') = '' then raise exception 'ID_REQUIRED'; end if;   -- id 없이 부르면 ictc_trash 가 전체를 복사하므로 막는다
  perform public.ictc_trash(p_kind, coalesce(p_board, 'main'), p_id, 'delete');
  delete from public.ictc_items where id = p_id and kind = p_kind and board = coalesce(p_board, 'main');
  -- 일정의 연동 주요업무 카드(id 'sch-'||일정id)는 같은 트랜잭션에서 함께 지운다 (화면이 따로 지우던 것을 서버가 보장)
  if p_kind = 'schedule' then
    perform public.ictc_trash('tasks', coalesce(p_board, 'main'), 'sch-' || p_id, 'delete');
    delete from public.ictc_items where id = 'sch-' || p_id and kind = 'tasks' and board = coalesce(p_board, 'main');
  end if;
end $$;

create or replace function public.ictc_replace(p_pin text, p_kind text, p_items jsonb, p_board text default 'main')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'ITEMS_REQUIRED'; end if;
  if jsonb_array_length(p_items) > 10000 then raise exception 'ITEM_TOO_LARGE'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) x where jsonb_typeof(x) <> 'object') then raise exception 'ITEMS_REQUIRED'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) x where length(coalesce(x->>'id', '')) > 100 or pg_column_size(x) > 65536) then raise exception 'ITEM_TOO_LARGE'; end if;
  if not exists (select 1 from public.ictc_boards where id = coalesce(p_board, 'main')) then raise exception 'BOARD_NOT_FOUND'; end if;
  perform public.ictc_trash(p_kind, coalesce(p_board, 'main'), null, 'replace');
  delete from public.ictc_items where kind = p_kind and board = coalesce(p_board, 'main');
  -- 같은 id 가 여러 번 나오면 마지막 것만. 다른 종류·대시보드에 이미 있는 id 는 건너뛴다(덮어쓰지 않음)
  insert into public.ictc_items (id, kind, board, data, updated_at)
  select distinct on (t.id) t.id, p_kind, coalesce(p_board, 'main'), t.x, now()
  from (select coalesce(e.x->>'id', gen_random_uuid()::text) as id, e.x, e.ord from jsonb_array_elements(p_items) with ordinality as e(x, ord)) t
  order by t.id, t.ord desc
  on conflict (id) do nothing;
end $$;

-- ---------- 대시보드 ----------
create or replace function public.ictc_boards(p_pin text)
returns table (id text, name text) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  return query select b.id, b.name from public.ictc_boards b order by (b.id <> 'main'), b.created_at;
end $$;

create or replace function public.ictc_board_add(p_pin text, p_id text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if length(trim(coalesce(p_id, ''))) = 0 or length(p_id) > 64 then raise exception 'ID_REQUIRED'; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'NAME_REQUIRED'; end if;
  if exists (select 1 from public.ictc_boards where id = p_id) then raise exception 'BOARD_EXISTS'; end if;
  insert into public.ictc_boards (id, name) values (p_id, left(trim(p_name), 60));
end $$;

create or replace function public.ictc_board_rename(p_pin text, p_id text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'NAME_REQUIRED'; end if;
  update public.ictc_boards set name = left(trim(p_name), 60) where id = p_id;
  if not found then raise exception 'BOARD_NOT_FOUND'; end if;
end $$;

create or replace function public.ictc_board_delete(p_pin text, p_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if p_id = 'main' then raise exception 'BOARD_PROTECTED'; end if;
  perform public.ictc_trash('schedule', p_id, null, 'board_delete');
  perform public.ictc_trash('tasks', p_id, null, 'board_delete');
  delete from public.ictc_items where board = p_id and kind in ('schedule', 'tasks');
  delete from public.ictc_boards where id = p_id;
end $$;

-- ---------- 개인업무 ----------
create or replace function public.ictc_user_check(p_id text, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select pin_hash into h from public.ictc_users where id = p_id;
  if h is null then raise exception 'USER_NOT_FOUND'; end if;
  if h <> crypt(coalesce(p_pin, ''), h) then
    perform public.ictc_fail_delay();
    raise exception 'USER_PIN_INVALID';
  end if;
end $$;

-- 등록: 팀 조회 PIN을 아는 사람(직원)만 가능
create or replace function public.ictc_user_register(p_view_pin text, p_id text, p_name text, p_pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_view_pin);
  if length(coalesce(p_id, '')) < 4 or length(p_id) > 20 then raise exception 'USER_ID_INVALID'; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'NAME_REQUIRED'; end if;
  if length(trim(coalesce(p_pin, ''))) < 4 then raise exception 'PIN_TOO_SHORT'; end if;   -- v4: 비밀번호 4자리
  if exists (select 1 from public.ictc_users where id = p_id) then raise exception 'USER_EXISTS'; end if;
  insert into public.ictc_users (id, name, pin_hash) values (p_id, left(trim(p_name), 20), crypt(p_pin, gen_salt('bf')));
  return left(trim(p_name), 20);
end $$;

create or replace function public.ictc_user_login(p_id text, p_pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_pin);
  return (select name from public.ictc_users where id = p_id);
end $$;

create or replace function public.ictc_user_set_pin(p_id text, p_old text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_old);
  if length(trim(coalesce(p_new, ''))) < 4 then raise exception 'PIN_TOO_SHORT'; end if;
  -- v4: 비밀번호(4자리)와 이름은 별개. 이름은 ictc_user_rename 으로만 바꾼다
  update public.ictc_users set pin_hash = crypt(trim(p_new), gen_salt('bf')) where id = p_id;
end $$;

-- 개인업무 비밀번호 초기화(담당자, 편집 PIN). 본인이 잊었을 때 새 4자리를 정해 알려 주고 바꾸게 한다
create or replace function public.ictc_user_reset_pin(p_edit_pin text, p_id text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  if length(trim(coalesce(p_new, ''))) < 4 then raise exception 'PIN_TOO_SHORT'; end if;
  update public.ictc_users set pin_hash = crypt(trim(p_new), gen_salt('bf')) where id = p_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
end $$;

-- 개인업무 이름 변경(본인, 비밀번호 확인). 등록 때는 '직원 1234' 같은 기본 이름이 들어가고 본인이 바꾼다
create or replace function public.ictc_user_set_name(p_id text, p_pin text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_pin);
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'NAME_REQUIRED'; end if;
  update public.ictc_users set name = left(trim(p_name), 20) where id = p_id;
end $$;

-- 개인업무 이름 수정(담당자, 편집 PIN). 업무 카드의 담당자 표시도 이 이름을 쓴다
create or replace function public.ictc_user_rename(p_edit_pin text, p_id text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'NAME_REQUIRED'; end if;
  update public.ictc_users set name = left(trim(p_name), 20) where id = p_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
end $$;

create or replace function public.ictc_personal_list(p_id text, p_pin text)
returns table (data jsonb, updated_at timestamptz) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_pin);
  return query select i.data, i.updated_at from public.ictc_items i
    where i.kind = 'personal' and i.board = p_id order by i.updated_at desc;
end $$;

create or replace function public.ictc_personal_save(p_id text, p_pin text, p_item jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_pin);
  perform public.ictc_check_item(p_item);
  insert into public.ictc_items (id, kind, board, data, updated_at)
  values (p_item->>'id', 'personal', p_id, p_item, now())
  on conflict (id) do update set data = excluded.data, updated_at = now()
  where public.ictc_items.kind = 'personal' and public.ictc_items.board = p_id;
end $$;

create or replace function public.ictc_personal_delete(p_id text, p_pin text, p_item_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_pin);
  if coalesce(p_item_id, '') = '' then raise exception 'ID_REQUIRED'; end if;
  perform public.ictc_trash('personal', p_id, p_item_id, 'personal_delete');
  delete from public.ictc_items where id = p_item_id and kind = 'personal' and board = p_id;
end $$;

-- 개인업무 사용자 목록: select * from ictc_users_list('편집PIN');
create or replace function public.ictc_users_list(p_edit_pin text)
returns table (id text, name text, created_at timestamptz, item_count bigint) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  return query select u.id, u.name, u.created_at,
    (select count(*) from public.ictc_items i where i.kind = 'personal' and i.board = u.id)
    from public.ictc_users u order by u.created_at;
end $$;

-- 개인업무 사용자 삭제(개인업무 포함): select ictc_user_delete('편집PIN', '뒤4자리');
create or replace function public.ictc_user_delete(p_edit_pin text, p_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  perform public.ictc_trash('personal', p_id, null, 'user_delete');
  delete from public.ictc_items where kind = 'personal' and board = p_id;
  delete from public.ictc_users where id = p_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
end $$;

-- ---------- 휴지통 (편집 PIN) ----------
-- 최근 삭제 항목 보기: select seq, kind, board, deleted_at, reason, data->>'title' from ictc_deleted_list('편집PIN');
--                    select * from ictc_deleted_list('편집PIN', 'schedule', 'main');   (종류·대시보드로 좁히기)
-- 복구:              select ictc_restore('편집PIN', 123);   (seq 값. 같은 id 가 다시 있으면 보관본으로 되돌림)
create or replace function public.ictc_deleted_list(p_edit_pin text, p_kind text default null, p_board text default null)
returns table (seq bigint, id text, kind text, board text, data jsonb, updated_at timestamptz, deleted_at timestamptz, reason text)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  delete from public.ictc_items_deleted x where x.deleted_at < now() - interval '30 days';   -- 삭제가 한동안 없어도 목록을 열 때 정리 (출력 컬럼명과 겹치므로 별칭 필수)
  return query select d.seq, d.id, d.kind, d.board, d.data, d.updated_at, d.deleted_at, d.reason from public.ictc_items_deleted d
    where (p_kind is null or d.kind = p_kind) and (p_board is null or d.board = p_board)
    order by d.deleted_at desc, d.seq desc limit 500;
end $$;

-- 일정을 복구하면 함께 지워진 연동 주요업무 카드('sch-'||일정id)도, 연동 카드를 복구하면 그 일정도 보관본이 있으면 함께 되살린다.
create or replace function public.ictc_restore(p_edit_pin text, p_seq bigint)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare d record; pseq bigint;
begin
  perform public.ictc_require_edit(p_edit_pin);
  select * into d from public.ictc_items_deleted where seq = p_seq;
  if not found then raise exception 'DELETED_NOT_FOUND'; end if;
  if d.kind = 'personal' and not exists (select 1 from public.ictc_users where id = d.board) then raise exception 'USER_NOT_FOUND'; end if;
  if d.kind in ('schedule', 'tasks') and not exists (select 1 from public.ictc_boards where id = d.board) then raise exception 'BOARD_NOT_FOUND'; end if;
  if d.kind = 'chat' and not exists (select 1 from public.ictc_chat_rooms where id = d.board) then raise exception 'CHAT_ROOM_NOT_FOUND'; end if;
  insert into public.ictc_items (id, kind, board, data, updated_at)
  values (d.id, d.kind, d.board, d.data, now())
  on conflict (id) do update set data = excluded.data, board = excluded.board, updated_at = now()
  where public.ictc_items.kind = excluded.kind;   -- 같은 id 가 다른 종류로 있으면 건드리지 않음
  delete from public.ictc_items_deleted where seq = p_seq;
  if d.kind = 'schedule' then
    select x.seq into pseq from public.ictc_items_deleted x where x.kind = 'tasks' and x.board = d.board and x.id = 'sch-' || d.id order by x.deleted_at desc, x.seq desc limit 1;
  elsif d.kind = 'tasks' and d.id like 'sch-%' then
    select x.seq into pseq from public.ictc_items_deleted x where x.kind = 'schedule' and x.board = d.board and x.id = substr(d.id, 5) order by x.deleted_at desc, x.seq desc limit 1;
  end if;
  if pseq is not null and not exists (select 1 from public.ictc_items i join public.ictc_items_deleted x on x.id = i.id where x.seq = pseq) then
    insert into public.ictc_items (id, kind, board, data, updated_at)
    select x.id, x.kind, x.board, x.data, now() from public.ictc_items_deleted x where x.seq = pseq
    on conflict (id) do nothing;
    delete from public.ictc_items_deleted where seq = pseq;
  end if;
end $$;

-- ---------- 관리 ----------
-- 편집 PIN 변경: select ictc_set_pin('기존편집PIN', '새편집PIN');
-- 조회 PIN 변경: select ictc_set_view_pin('편집PIN', '새조회PIN');   ('' 이면 누구나 조회)
-- 개인업무 비밀번호 초기화: select ictc_user_reset_pin('편집PIN', '뒤4자리', '새비밀번호4자리');  이름 수정: select ictc_user_rename('편집PIN', '뒤4자리', '바른이름');
create or replace function public.ictc_set_pin(p_old text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_old);
  if length(coalesce(p_new, '')) < 4 then raise exception 'PIN_TOO_SHORT'; end if;
  update public.ictc_settings set value = p_new where key = 'edit_pin';
end $$;
create or replace function public.ictc_set_view_pin(p_edit_pin text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  insert into public.ictc_settings (key, value) values ('view_pin', coalesce(p_new, ''))
  on conflict (key) do update set value = excluded.value;
end $$;


-- ---------- 41망 톡방 (v6: 부서별 톡방 + 입장코드) ----------
-- 입장코드는 해시로만 저장. 기본 코드는 최초 설치 때만 들어가고(on conflict do nothing) 이후 ictc_chat_set_code 로 바꾼다.
create table if not exists public.ictc_chat_rooms (
  id          text primary key,
  name        text not null,
  code_hash   text not null,
  sort        int  not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.ictc_chat_rooms enable row level security;
-- 함수 밖에서는 search_path 에 extensions 가 없어 gen_salt 를 못 찾으므로 DO 블록 안에서 경로를 지정한다
do $$
begin
  perform set_config('search_path', 'public, extensions', true);
  insert into public.ictc_chat_rooms (id, name, code_hash, sort) values
    ('ictc',        '지휘역량강화센터', crypt('5948', gen_salt('bf')), 1),
    ('edu-support', '교육지원과',       crypt('5914', gen_salt('bf')), 2),
    ('edu-plan',    '교육기획과',       crypt('5926', gen_salt('bf')), 3),
    ('training',    '훈련운영과',       crypt('5527', gen_salt('bf')), 4)
  on conflict (id) do nothing;
end $$;
-- v5 에서 'main' 톡방에 쓴 글은 지휘역량강화센터 톡방으로
update public.ictc_items set board = 'ictc' where kind = 'chat' and board = 'main';

create or replace function public.ictc_chat_check(p_room text, p_code text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select code_hash into h from public.ictc_chat_rooms where id = p_room;
  if h is null then raise exception 'CHAT_ROOM_NOT_FOUND'; end if;
  if h <> crypt(coalesce(p_code, ''), h) then
    perform public.ictc_fail_delay();
    raise exception 'CHAT_CODE_INVALID';
  end if;
end $$;

create or replace function public.ictc_chat_rooms(p_pin text)
returns table (id text, name text, sort int) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  return query select r.id, r.name, r.sort from public.ictc_chat_rooms r order by r.sort, r.created_at;
end $$;

-- 입장: 코드가 맞으면 톡방 이름을 돌려준다
create or replace function public.ictc_chat_join(p_pin text, p_room text, p_code text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  perform public.ictc_chat_check(p_room, p_code);
  return (select name from public.ictc_chat_rooms where id = p_room);
end $$;

create or replace function public.ictc_chat_list(p_pin text, p_room text, p_code text)
returns table (data jsonb, updated_at timestamptz) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  perform public.ictc_chat_check(p_room, p_code);
  return query select i.data, i.updated_at from public.ictc_items i where i.kind = 'chat' and i.board = p_room order by i.updated_at desc;
end $$;

create or replace function public.ictc_chat_save(p_pin text, p_room text, p_code text, p_item jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  perform public.ictc_chat_check(p_room, p_code);
  perform public.ictc_check_item(p_item);
  -- 화면의 '글 삭제'는 {deleted:true} 자리표시로 덮어쓰는 방식이므로, 원문은 이때 휴지통(30일)에 남긴다
  if p_item->'deleted' = 'true'::jsonb then
    insert into public.ictc_items_deleted (id, kind, board, data, updated_at, reason)
    select i.id, i.kind, i.board, i.data, i.updated_at, 'delete' from public.ictc_items i
     where i.id = p_item->>'id' and i.kind = 'chat' and i.board = p_room and coalesce(i.data->'deleted', 'false'::jsonb) <> 'true'::jsonb;
  end if;
  insert into public.ictc_items (id, kind, board, data, updated_at)
  values (p_item->>'id', 'chat', p_room, p_item, now())
  on conflict (id) do update set data = excluded.data, updated_at = now()
  where public.ictc_items.kind = 'chat' and public.ictc_items.board = p_room;
  -- 톡방마다 최근 300개만 보관. 밀려난 옛 글은 휴지통 없이 지운다
  delete from public.ictc_items where kind = 'chat' and board = p_room and id not in (
    select id from public.ictc_items where kind = 'chat' and board = p_room order by updated_at desc limit 300);
end $$;

create or replace function public.ictc_chat_delete(p_pin text, p_room text, p_code text, p_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  perform public.ictc_chat_check(p_room, p_code);
  if coalesce(p_id, '') = '' then raise exception 'ID_REQUIRED'; end if;
  perform public.ictc_trash('chat', p_room, p_id, 'delete');
  delete from public.ictc_items where id = p_id and kind = 'chat' and board = p_room;
end $$;

-- 관리(편집 PIN): 입장코드 변경, 이름 변경, 톡방 추가·삭제
create or replace function public.ictc_chat_set_code(p_edit_pin text, p_room text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  if length(trim(coalesce(p_new, ''))) < 4 then raise exception 'CHAT_CODE_TOO_SHORT'; end if;
  update public.ictc_chat_rooms set code_hash = crypt(trim(p_new), gen_salt('bf')) where id = p_room;
  if not found then raise exception 'CHAT_ROOM_NOT_FOUND'; end if;
end $$;
create or replace function public.ictc_chat_room_rename(p_edit_pin text, p_room text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  if length(trim(coalesce(p_name, ''))) < 1 then raise exception 'NAME_REQUIRED'; end if;
  update public.ictc_chat_rooms set name = left(trim(p_name), 60) where id = p_room;
  if not found then raise exception 'CHAT_ROOM_NOT_FOUND'; end if;
end $$;
create or replace function public.ictc_chat_room_add(p_edit_pin text, p_id text, p_name text, p_code text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  if length(trim(coalesce(p_id, ''))) < 1 or length(trim(coalesce(p_name, ''))) < 1 then raise exception 'NAME_REQUIRED'; end if;
  if length(trim(p_id)) > 64 then raise exception 'ID_REQUIRED'; end if;
  if length(trim(coalesce(p_code, ''))) < 4 then raise exception 'CHAT_CODE_TOO_SHORT'; end if;
  if exists (select 1 from public.ictc_chat_rooms where id = trim(p_id)) then raise exception 'CHAT_ROOM_EXISTS'; end if;
  insert into public.ictc_chat_rooms (id, name, code_hash, sort)
  values (trim(p_id), left(trim(p_name), 60), crypt(trim(p_code), gen_salt('bf')), coalesce((select max(sort) from public.ictc_chat_rooms), 0) + 1);
end $$;
create or replace function public.ictc_chat_room_delete(p_edit_pin text, p_room text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  perform public.ictc_trash('chat', p_room, null, 'room_delete');
  delete from public.ictc_items where kind = 'chat' and board = p_room;
  delete from public.ictc_chat_rooms where id = p_room;
  if not found then raise exception 'CHAT_ROOM_NOT_FOUND'; end if;
end $$;

-- ---------- 아침 브리핑 (v6.6) ----------
-- 평일 07:00(한국 시간) 톡방마다 "오늘 일정 + 소방 뉴스 5개" 글을 '브리핑' 이름으로 올린다.
-- 글 id 는 brief-<톡방>-<날짜> 하나뿐이라 몇 번 불러도 하루 한 번만 올라간다. 톡방 ↔ 대시보드는 이름이 같은 것으로 잇고, 없으면 main.
create or replace function public.ictc_dt(p text)
returns date language plpgsql immutable set search_path = public, extensions as $$
begin return nullif(p, '')::date; exception when others then return null; end $$;

-- 소방 뉴스(v6.12): GitHub Actions(fire-news.yml)가 평일 아침 골라 넣는다. anon 은 못 읽고(RLS), 브리핑 함수가 읽어 글에 붙인다
create table if not exists public.ictc_news (day date primary key, items jsonb not null default '[]'::jsonb, updated_at timestamptz not null default now());
alter table public.ictc_news enable row level security;
revoke all on public.ictc_news from anon, authenticated;
create or replace function public.ictc_news_set(p_day date, p_items jsonb)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare r record; cnt int := 0; b text; mid text;
begin
  insert into public.ictc_news (day, items, updated_at) values (p_day, coalesce(p_items, '[]'::jsonb), now())
  on conflict (day) do update set items = excluded.items, updated_at = now();
  -- 이미 올라간 그날 자동 브리핑 글의 본문을 뉴스가 붙은 문장으로 바꾼다(id 그대로 → 읽음 상태 유지)
  for r in select id, name from public.ictc_chat_rooms loop
    mid := 'brief-' || r.id || '-' || to_char(p_day, 'YYYYMMDD');
    if exists (select 1 from public.ictc_items where id = mid and kind = 'chat') then
      select id into b from public.ictc_boards where name = r.name limit 1; b := coalesce(b, 'main');
      update public.ictc_items set data = data || jsonb_build_object('text', public.ictc_briefing_text(b, r.name, p_day, false)) where id = mid and kind = 'chat';
      cnt := cnt + 1;
    end if;
  end loop;
  return cnt;
end $$;

drop function if exists public.ictc_briefing_text(text, text, date);
drop function if exists public.ictc_chat_briefing(date);
create or replace function public.ictc_briefing_text(p_board text, p_room_name text, p_date date, p_manual boolean default false)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  dow text[] := array['일','월','화','수','목','금','토'];
  txt text := ''; r record; d date; n int; k int; line text; news jsonb;
begin
  txt := '📋 ' || extract(month from p_date)::int || '월 ' || extract(day from p_date)::int || '일(' || dow[extract(dow from p_date)::int + 1] || ') 아침 브리핑 · ' || p_room_name || (case when p_manual then ' · 수동 게시' else '' end);
  d := p_date;
  select count(*) into n from public.ictc_items i where i.kind = 'schedule' and i.board = p_board
    and public.ictc_dt(i.data->>'date') <= d and coalesce(public.ictc_dt(i.data->>'endDate'), public.ictc_dt(i.data->>'date')) >= d;
  txt := txt || E'\n오늘 일정 ' || n || '건';
  k := 0;
  for r in
    select i.data as it,
           (coalesce(i.data->'tags', jsonb_build_array(i.data->'tag')) @> '["주요업무"]'::jsonb) as major,
           public.ictc_dt(i.data->>'date') as sd, coalesce(public.ictc_dt(i.data->>'endDate'), public.ictc_dt(i.data->>'date')) as ed
      from public.ictc_items i where i.kind = 'schedule' and i.board = p_board
       and public.ictc_dt(i.data->>'date') <= d and coalesce(public.ictc_dt(i.data->>'endDate'), public.ictc_dt(i.data->>'date')) >= d
     order by major desc, coalesce(i.data->>'start', '') , i.data->>'title'
  loop
    k := k + 1;
    if k > 8 then txt := txt || E'\n … 외 ' || (n - 8) || '건'; exit; end if;
    line := ' ' || coalesce(nullif(r.it->>'start', ''), '종일') || ' ' || (case when r.major then '★ ' else '' end) || coalesce(r.it->>'title', '');
    if coalesce(r.it->>'place', '') <> '' then line := line || ' · ' || (r.it->>'place'); end if;
    if coalesce(r.it->>'owner', '') <> '' then line := line || ' · ' || (r.it->>'owner'); end if;
    if r.ed > r.sd then line := line || ' (' || (d - r.sd + 1) || '/' || (r.ed - r.sd + 1) || '일차)'; end if;
    txt := txt || E'\n' || line;
  end loop;
  -- 소방 뉴스(전날 07:00~당일 07:00, DB 안 수집 또는 GitHub Actions 가 골라 ictc_news 에 넣음). 없으면 이 절은 생략
  select items into news from public.ictc_news where day = p_date;
  if news is not null and jsonb_array_length(news) > 0 then
    txt := txt || E'\n소방 뉴스'; k := 0;
    for r in select value as it from jsonb_array_elements(news) loop
      k := k + 1; if k > 5 then exit; end if;
      txt := txt || E'\n ' || k || '. ' || coalesce(r.it->>'title', '') || ' (' || coalesce(r.it->>'press', '') || ') ' || coalesce(r.it->>'url', '');
    end loop;
  end if;
  return txt;
end $$;

-- p_manual=true(관리자 '브리핑 테스트'): 하루 한 번 제한 없이 매번 새 글(id 에 시각 포함)로 올리고, 자동 08:00 게시에는 영향 없음
create or replace function public.ictc_chat_briefing(p_date date default null, p_manual boolean default false)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Seoul')::date); r record; b text; mid text; cnt int := 0; txt text;
begin
  for r in select id, name from public.ictc_chat_rooms order by sort loop
    mid := 'brief-' || r.id || '-' || to_char(d, 'YYYYMMDD') || (case when p_manual then '-m' || (extract(epoch from clock_timestamp()) * 1000)::bigint else '' end);
    if not p_manual and exists (select 1 from public.ictc_items where id = mid) then continue; end if;
    select id into b from public.ictc_boards where name = r.name limit 1; b := coalesce(b, 'main');
    txt := public.ictc_briefing_text(b, r.name, d, p_manual);
    insert into public.ictc_items (id, kind, board, data, updated_at)
    values (mid, 'chat', r.id, jsonb_build_object('id', mid, 'text', txt, 'name', '브리핑', 'dev', 'bot', 'bot', true,
            'created', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), now());
    delete from public.ictc_items where kind = 'chat' and board = r.id and id not in (
      select id from public.ictc_items where kind = 'chat' and board = r.id order by updated_at desc limit 300);
    cnt := cnt + 1;
  end loop;
  return cnt;
end $$;

-- 화면이 부르는 보충 게시: 예약 실행이 어떤 이유로 안 돌았을 때 7시 이후 처음 연 사람의 화면이 대신 올린다(평일 · 한국 시간)
create or replace function public.ictc_chat_briefing_post(p_pin text)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare t timestamp := now() at time zone 'Asia/Seoul';
begin
  perform public.ictc_require_view(p_pin);
  if extract(isodow from t) >= 6 or extract(hour from t) < 7 then return 0; end if;
  return public.ictc_chat_briefing(t::date);
end $$;

-- 관리자가 지금 바로 올리기(테스트·수동): 요일·시각 조건 없이 오늘 것이 없는 톡방에 올린다
create or replace function public.ictc_chat_briefing_now(p_edit_pin text)
returns int language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  return public.ictc_chat_briefing((now() at time zone 'Asia/Seoul')::date, true);
end $$;

-- ---------- 소방 뉴스 수집을 DB 안에서 (v6.13, pg_net) ----------
-- GitHub 예약이 돌지 않는 날에도 뉴스가 붙도록, Supabase 의 pg_net 으로 Google 뉴스 RSS 를 받아 SQL 이 직접 3개를 고른다.
-- 순위 기준은 server/fire_news.py 와 같다(주요 언론사 ×3 + 그 밖 ×1 + 기사 수 ×0.3 + 사고·인명 +3, 해외 −6, 행사·홍보 −4).
create table if not exists public.ictc_news_req (day date not null, q text not null, req_id bigint not null, created_at timestamptz not null default now());
alter table public.ictc_news_req enable row level security;
revoke all on public.ictc_news_req from anon, authenticated;

-- RSS 문서들(xml 배열)에서 창 안 기사를 모아 5개를 고른다(인천 관련 최우선). 순수 함수라 로컬에서도 검사할 수 있다
create or replace function public.ictc_news_rank(p_docs xml[], p_day date)
returns jsonb language plpgsql set search_path = public, extensions as $$
declare
  w_start timestamptz := ((p_day - 1)::timestamp + interval '7 hours') at time zone 'Asia/Seoul';   -- 전날 07:00 ~ 당일 07:00 (24시간)
  w_end   timestamptz := (p_day::timestamp + interval '7 hours') at time zone 'Asia/Seoul';
  major text[] := array['연합뉴스','KBS','MBC','SBS','YTN','JTBC','조선일보','중앙일보','동아일보','한겨레','경향신문','뉴시스','뉴스1','한국일보','서울신문','국민일보','세계일보','문화일보','매일경제','한국경제','연합뉴스TV','MBN','TV조선','채널A'];
  foreign_w text[] := array['홍콩','중국','일본','미국','대만','영국','프랑스','독일','러시아','우크라이나','인도','호주','캐나다','유럽','해외','베트남','태국','필리핀','인도네시아','이스라엘','이란','터키','튀르키예','브라질','멕시코','뉴욕','도쿄','파리','런던'];
  pr_w text[] := array['개최','성황리','훈련','캠페인','협약','MOU','홍보','간담회','위촉','수여','표창','방문','시상','발대식','점검 실시','교육 실시','행사','기념','업무협약','워크숍','세미나','봉사'];
  inc_w text[] := array['화재','불','사망','숨져','순직','부상','구조','대피','폭발','붕괴','사고','진화','전소','화상','참사','이송','인명'];
  other_w text[] := array['울산','대전','부산','대구','광주','세종','강원','충북','충남','전북','전남','경북','경남','제주','춘천','원주','청주','천안','전주','목포','포항','창원','김해','진주','구미','경주','여수','순천','군산','익산','장수','사천','통영','거제','안동','강릉','속초'];   -- 다른 지역의 지역 사고 −5
  nat_w text[] := array['사망','숨져','순직','참사','대형','전국','잇따라','동시다발','소방청','정부','국회','행정안전부','법안','개정','예산','처우','인력'];   -- 전국적 사건·정책 +3/개(최대 9)
  city_w text[] := array['인천'];   -- 시 단위: 사건·정책 모두 최우선(+100)
  gu_w text[] := array['부평','계양','미추홀','연수구','남동구','송도','영종','청라','검단','강화군','강화도','옹진','인천공항','인천항'];   -- 구 단위: 사건만 최우선, 정책·행사는 보통 기사
  death_w text[] := array['사망','숨져','숨진','숨졌','순직','참사'];   -- 사망 +6
  trivia_w text[] := array['소동','해프닝','뱀','고양이','강아지','개구리','벌집','말벌','동물','구출 작전','열쇠'];   -- 가벼운 해프닝 −10
  opinion_w text[] := array['시론','칼럼','사설','기고','논설','인터뷰','기자수첩'];   -- 의견·칼럼 −6
  noharm_w text[] := array['인명피해 없','인명 피해 없','다친 사람 없','부상자 없'];   -- 인명피해 없는 사고 −3(인천 제외)
  v_pr boolean; v_inc boolean; v_city boolean; v_gu boolean;
  stop_w text[] := array['소방','소방관','소방서','소방청','소방본부','화재','불','발생','관련','오늘','내일','어제','속보','단독','영상','사진','종합','기자','뉴스','인명피해','없어','없음','만에','추정','원인','조사','당국','경찰','긴급','현장','오전','오후','새벽','시간'];
  doc xml; it xml; v_t text; v_l text; v_p text; v_pd text; v_ts timestamptz; v_tok text[]; r record; c record; best int; k int; out jsonb := '[]'::jsonb; rep record; titles text; s numeric; n_major int; n_press int; n_items int;
begin
  create temp table if not exists tmp_news (id serial, title text, press text, url text, ts timestamptz, tok text[], cl int) on commit drop;
  create temp table if not exists tmp_cl (id serial, tok text[]) on commit drop;
  delete from tmp_news; delete from tmp_cl;
  foreach doc in array coalesce(p_docs, array[]::xml[]) loop
    for it in select unnest(xpath('/rss/channel/item', doc)) loop
      v_t := (xpath('/item/title/text()', it))[1]::text; v_l := (xpath('/item/link/text()', it))[1]::text; v_p := coalesce((xpath('/item/source/text()', it))[1]::text, '');   -- 조각(xml)에는 절대 경로로
      v_pd := (xpath('/item/pubDate/text()', it))[1]::text;
      if v_t is null or v_l is null or v_pd is null or v_t = '' then continue; end if;
      if v_p = '' and position(' - ' in v_t) > 0 then v_p := trim(substring(v_t from '.* - (.*)$')); end if;
      if position(' - ' in v_t) > 0 then v_t := trim(regexp_replace(v_t, ' - [^-]*$', '')); end if;
      v_t := regexp_replace(replace(replace(replace(replace(replace(v_t, '&amp;', '&'), '&gt;', '>'), '&lt;', '<'), '&quot;', '"'), '&#39;', ''''), '\s*>\s*뉴스\s*$', '');   -- 이중 이스케이프·꼬리말 정리
      begin v_ts := (regexp_replace(trim(regexp_replace(v_pd, '^[A-Za-z]+,\s*', '')), '\s+(GMT|UTC|\+0000)$', ''))::timestamp at time zone 'UTC';
      exception when others then continue; end;
      if v_ts < w_start or v_ts >= w_end then continue; end if;
      if exists (select 1 from tmp_news x where x.title = v_t and x.press = v_p) then continue; end if;
      -- 같은 뜻 통일 → 단어 추출 → 숫자·단위 제외 → 불용어(조사 붙은 꼴 포함) 제외 → 앞 3자
      v_tok := array(select distinct left(m[1], 2) from regexp_matches(regexp_replace(regexp_replace(regexp_replace(v_t, '다쳤|다쳐', '부상', 'g'), '숨졌|숨져|숨진', '사망', 'g'), '불길|진압', '진화', 'g'), '([가-힣A-Za-z0-9]{2,})', 'g') m
                      where m[1] !~ '^\d+(명|시간|분|건|일|층|대|곳|여|차|호|%)?$' and not exists (select 1 from unnest(stop_w) st where m[1] = st or (length(st) >= 2 and m[1] like st || '%')));
      insert into tmp_news (title, press, url, ts, tok) values (v_t, v_p, v_l, v_ts, v_tok);
    end loop;
  end loop;
  -- 같은 사건 묶기: 단어 2개 이상 겹치고 1/5 이상, 또는 3개 이상 겹침
  for r in select * from tmp_news order by ts desc loop
    best := null;
    for c in select * from tmp_cl order by id loop
      k := cardinality(array(select unnest(r.tok) intersect select unnest(c.tok)));   -- 묶음의 '첫 기사' 단어와 비교(눈덩이 방지)
      if cardinality(r.tok) > 0 and ((k >= 2 and k::numeric / greatest(cardinality(array(select unnest(r.tok) union select unnest(c.tok))), 1) >= 0.2) or k >= 3) then best := c.id; exit; end if;
    end loop;
    if best is null then insert into tmp_cl (tok) values (r.tok) returning id into best; end if;
    update tmp_news set cl = best where id = r.id;
  end loop;
  -- 점수
  for c in
    select cl, string_agg(title, ' / ') as titles, count(distinct press) as n_press, count(*) as n_items,
           count(distinct press) filter (where exists (select 1 from unnest(major) m where press like '%' || m || '%')) as n_major, max(ts) as last_ts
      from tmp_news group by cl
  loop
    s := c.n_major * 3 + (c.n_press - c.n_major) * 1 + c.n_items * 0.3;
    v_pr := exists (select 1 from unnest(pr_w) w where c.titles like '%' || w || '%');
    v_inc := (not v_pr) and exists (select 1 from unnest(inc_w) w where c.titles like '%' || w || '%');
    if v_pr then s := s - 4; elsif v_inc then s := s + 3; end if;
    if exists (select 1 from unnest(foreign_w) w where c.titles like '%' || w || '%') then s := s - 15; end if;   -- 해외 사건은 사망·참사라도 뒤로
    v_city := exists (select 1 from unnest(city_w) w where c.titles like '%' || w || '%'); v_gu := exists (select 1 from unnest(gu_w) w where c.titles like '%' || w || '%');
    if (v_inc and (v_city or v_gu)) or (v_city and not v_pr) then s := s + 100;   -- 인천 사건(구 단위 포함)·인천시 단위 정책은 맨 위. 구 단위 정책·행사는 보통 기사
    elsif (not v_city and not v_gu) and exists (select 1 from unnest(other_w) w where c.titles like '%' || w || '%') then s := s - 8; end if;
    if exists (select 1 from unnest(death_w) w where c.titles like '%' || w || '%') then s := s + 6; end if;   -- 사망 추가 가점
    if exists (select 1 from unnest(trivia_w) w where c.titles like '%' || w || '%') then s := s - 10; end if;   -- 해프닝 감점
    if exists (select 1 from unnest(opinion_w) w where c.titles like '%' || w || '%') then s := s - 6; end if;   -- 칼럼·시론 감점
    if not (v_city or v_gu) and exists (select 1 from unnest(noharm_w) w where c.titles like '%' || w || '%') then s := s - 3; end if;   -- 인명피해 없는 사고(인천 제외) 소폭 감점
    s := s + least(3, (select count(*) from unnest(nat_w) w where c.titles like '%' || w || '%')) * 3;
    insert into tmp_news (title, press, url, ts, tok, cl) values ('__score__', s::text, c.last_ts::text, c.last_ts, null, c.cl);
  end loop;
  k := 0;
  for c in select cl, press::numeric as score, ts as last_ts from tmp_news where title = '__score__' order by press::numeric desc, ts desc loop
    k := k + 1; if k > 5 then exit; end if;
    select title, press, url, ts into rep from tmp_news x where x.cl = c.cl and x.title <> '__score__'
      order by coalesce((select min(i) from unnest(major) with ordinality as m(name, i) where x.press like '%' || m.name || '%'), 99), ts desc limit 1;
    out := out || jsonb_build_object('title', rep.title, 'press', rep.press, 'url', rep.url, 'time', to_char(rep.ts at time zone 'Asia/Seoul', 'HH24:MI'),
                  'outlets', (select count(distinct press) from tmp_news x where x.cl = c.cl and x.title <> '__score__'));
  end loop;
  return out;
end $$;

-- URL 인코딩(한글 검색어). pg_net 은 주소를 그대로 보내므로 직접 %XX 로 바꾼다
create or replace function public.ictc_urlencode(p text)
returns text language sql immutable set search_path = public, extensions as $$
  select string_agg(case when chr(get_byte(b, i)) ~ '^[A-Za-z0-9._~-]$' then chr(get_byte(b, i)) else '%' || upper(lpad(to_hex(get_byte(b, i)), 2, '0')) end, '' order by i)
    from (select convert_to(p, 'UTF8') as b) s, generate_series(0, length(convert_to(p, 'UTF8')) - 1) as i;
$$;

-- 1) RSS 요청 보내기(pg_net, 비동기). 결과는 net._http_response 에 쌓인다
create or replace function public.ictc_news_fetch(p_day date default null)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_day, (now() at time zone 'Asia/Seoul')::date); q text; rid bigint; cnt int := 0;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then return 0; end if;
  delete from public.ictc_news_req where day < d - 2;
  foreach q in array array['소방', '소방관', '화재', '소방서 구조', '인천 소방'] loop
    rid := net.http_get('https://news.google.com/rss/search?q=' || public.ictc_urlencode(q) || '&hl=ko&gl=KR&ceid=KR:ko',
                        '{}'::jsonb, '{"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36", "Accept-Language": "ko-KR,ko;q=0.9"}'::jsonb, 15000);
    insert into public.ictc_news_req (day, q, req_id) values (d, q, rid); cnt := cnt + 1;
  end loop;
  return cnt;
end $$;

-- 2) 받은 응답으로 3개를 고르고 ictc_news 에 넣어 오늘 브리핑에 붙인다. 응답이 아직 없으면 0
create or replace function public.ictc_news_pick(p_day date default null)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_day, (now() at time zone 'Asia/Seoul')::date); docs xml[] := array[]::xml[]; r record; x xml; picked jsonb;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then return 0; end if;
  for r in execute 'select r.content from public.ictc_news_req q join net._http_response r on r.id = q.req_id where q.day = $1 and r.status_code = 200' using d loop
    begin x := r.content::xml; docs := docs || x; exception when others then continue; end;
  end loop;
  if cardinality(docs) = 0 then return 0; end if;
  picked := public.ictc_news_rank(docs, d);
  if jsonb_array_length(picked) = 0 then return 0; end if;
  perform public.ictc_news_set(d, picked);
  return jsonb_array_length(picked);
end $$;

-- 예약 실행(pg_cron): 평일 07:00 KST = UTC 일~목 22:00. 확장이 없으면(로컬 PostgreSQL·사전 검사) 건너뛴다.
-- Supabase 에서 create extension 이 거부되면 대시보드 → Database → Extensions 에서 pg_cron 을 켜고 이 파일을 한 번 더 실행하면 등록된다.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then raise notice 'pg_cron 을 만들지 못했습니다(%). 대시보드에서 켠 뒤 다시 실행하세요.', sqlerrm;
  end;
  begin
    create extension if not exists pg_net;
  exception when others then raise notice 'pg_net 을 만들지 못했습니다(%). 대시보드 → Database → Extensions 에서 pg_net 을 켜면 뉴스가 DB 안에서 수집됩니다.', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('sail41-briefing', 'sail41-news-fetch-1', 'sail41-news-fetch-2', 'sail41-news-pick-1', 'sail41-news-pick-2');
    perform cron.schedule('sail41-news-fetch-1', '45 21 * * 0-4', 'select public.ictc_news_fetch()');   -- 06:45 KST RSS 요청
    perform cron.schedule('sail41-news-pick-1',  '57 21 * * 0-4', 'select public.ictc_news_pick()');    -- 06:57 고르기 → 07:00 브리핑에 실림
    perform cron.schedule('sail41-briefing',     '0 22 * * 0-4',  'select public.ictc_chat_briefing()'); -- 07:00 브리핑
    perform cron.schedule('sail41-news-fetch-2', '1 22 * * 0-4',  'select public.ictc_news_fetch()');   -- 07:01 창(07:00까지) 완성용 재요청
    perform cron.schedule('sail41-news-pick-2',  '12 22 * * 0-4', 'select public.ictc_news_pick()');    -- 07:12 다시 골라 브리핑 본문 갱신
    raise notice 'pg_cron 예약 등록: 브리핑 07:00 · 뉴스 06:45/06:57/07:01/07:12 (KST)';
  end if;
end $$;

-- ---------- 첨부파일 저장소 (Supabase Storage, v6.1 · 일정·업무 사진 v6.5) ----------
-- 버킷 sail41 (공개 읽기, 파일당 100MB 설정. 단 Supabase 무료 요금제는 프로젝트 전체 상한이 파일당 50MB 라 그 이상은 거부됨). 업로드는 anon 키로 chat/ 경로에만, 허용 형식 제한.
-- 로컬 PostgreSQL 에는 storage 스키마가 없으므로 있을 때만 실행한다.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('sail41', 'sail41', true, 104857600,
      array['image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif','application/pdf','text/plain','text/csv',
            'application/zip','application/x-hwp','application/haansofthwp','application/vnd.hancom.hwp','application/vnd.hancom.hwpx','application/x-hwpx',
            'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation','application/octet-stream'])
    on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
    execute 'drop policy if exists "sail41 chat upload" on storage.objects';
    -- 경로는 chat/<톡방id>/<난수>.<확장자> (41망) 또는 items/<schedule|tasks|personal|briefing>/<난수>.<확장자> (일정·업무 사진 v6.5, 브리핑 공유 이미지 v6.20) 세 단계만
    -- (화면 chatUpload · itemUpload 의 key 형식과 같아야 함). 수정·삭제 정책은 없으므로 anon 은 올린 파일을 바꾸거나 지울 수 없다
    execute $p$create policy "sail41 chat upload" on storage.objects for insert to anon, authenticated
      with check (bucket_id = 'sail41' and ((storage.foldername(name))[1] = 'chat' or (storage.foldername(name))[1] = 'items')
        and name ~ '^(chat/[A-Za-z0-9_.%-]{1,64}|items/(schedule|tasks|personal|briefing))/[A-Za-z0-9_.-]{1,80}$')$p$;   -- briefing: 카카오톡 공유용 브리핑 이미지
    execute 'drop policy if exists "sail41 public read" on storage.objects';
    execute $p$create policy "sail41 public read" on storage.objects for select to anon, authenticated using (bucket_id = 'sail41')$p$;
  end if;
end $$;

-- ---------- 권한 ----------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname as name from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'ictc\_%' loop
    execute format('revoke all on function %s from public', f.sig);
    if f.name in ('ictc_fail_delay', 'ictc_check_pin', 'ictc_check_view_pin', 'ictc_user_check', 'ictc_require_view', 'ictc_require_edit', 'ictc_trash', 'ictc_chat_check', 'ictc_check_item', 'ictc_dt', 'ictc_briefing_text', 'ictc_chat_briefing', 'ictc_news_set', 'ictc_news_rank', 'ictc_news_fetch', 'ictc_news_pick', 'ictc_urlencode') then
      execute format('revoke all on function %s from anon, authenticated', f.sig);   -- 내부 전용
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
