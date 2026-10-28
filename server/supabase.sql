-- ============================================================
-- SAIL:41 (지휘역량강화센터 일정·업무 보드) - Supabase 설정 (v6.11: 브리핑 평일 07:00 · v6.10: 관리자 브리핑 테스트는 매번 새 글 · v6.9: 브리핑 내일 일정은 건수만 · v6.8: 브리핑 목록에서 기한 지난 업무 제외 · v6.7: 브리핑 지금 올리기(관리자) · v6.6: 평일 08:00 아침 브리핑(pg_cron) · v6.5: 일정·업무 사진 첨부 경로 items/ 허용 · v6.4: 입력 크기 제한 · 일정↔연동카드 삭제·복구 일관성 · 41망 삭제 글 휴지통 · v6.3: 첨부 100MB · v6: 부서별 톡방 + 입장코드)
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
-- 평일 07:00(한국 시간) 톡방마다 "오늘·내일 일정 + 업무 기한" 요약 글을 '브리핑' 이름으로 올린다.
-- 글 id 는 brief-<톡방>-<날짜> 하나뿐이라 몇 번 불러도 하루 한 번만 올라간다. 톡방 ↔ 대시보드는 이름이 같은 것으로 잇고, 없으면 main.
create or replace function public.ictc_dt(p text)
returns date language plpgsql immutable set search_path = public, extensions as $$
begin return nullif(p, '')::date; exception when others then return null; end $$;

drop function if exists public.ictc_briefing_text(text, text, date);
drop function if exists public.ictc_chat_briefing(date);
create or replace function public.ictc_briefing_text(p_board text, p_room_name text, p_date date, p_manual boolean default false)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  dow text[] := array['일','월','화','수','목','금','토'];
  txt text := ''; r record; d date; n int; k int; late int; today_due int; prog int; line text;
begin
  txt := '📋 ' || extract(month from p_date)::int || '월 ' || extract(day from p_date)::int || '일(' || dow[extract(dow from p_date)::int + 1] || ') 아침 브리핑 · ' || p_room_name || (case when p_manual then ' · 수동 게시' else '' end);
  foreach d in array array[p_date, p_date + 1] loop
    select count(*) into n from public.ictc_items i where i.kind = 'schedule' and i.board = p_board
      and public.ictc_dt(i.data->>'date') <= d and coalesce(public.ictc_dt(i.data->>'endDate'), public.ictc_dt(i.data->>'date')) >= d;
    txt := txt || E'\n' || (case when d = p_date then '오늘' else '내일' end) || ' 일정 ' || n || '건';
    if d <> p_date then continue; end if;   -- 내일은 건수만, 목록은 오늘 일정만
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
  end loop;
  select count(*) filter (where public.ictc_dt(i.data->>'due') < p_date),
         count(*) filter (where public.ictc_dt(i.data->>'due') = p_date),
         count(*) filter (where i.data->>'status' = '진행중')
    into late, today_due, prog
    from public.ictc_items i where i.kind = 'tasks' and i.board = p_board and coalesce(i.data->>'status', '') not in ('완료', '보류');
  txt := txt || E'\n업무: 기한 지남 ' || late || '건 · 오늘 기한 ' || today_due || '건 · 진행중 ' || prog || '건';
  k := 0;
  for r in
    select i.data as it, public.ictc_dt(i.data->>'due') as due from public.ictc_items i
     where i.kind = 'tasks' and i.board = p_board and coalesce(i.data->>'status', '') not in ('완료', '보류') and public.ictc_dt(i.data->>'due') = p_date
     order by i.data->>'title'   -- 목록에는 오늘 기한만 (기한 지난 업무는 건수만)
  loop
    k := k + 1;
    if k > 6 then txt := txt || E'\n … 외 ' || (today_due - 6) || '건'; exit; end if;
    line := ' ! ' || coalesce(r.it->>'title', '');
    if coalesce(r.it->>'owner', '') <> '' then line := line || ' · ' || (r.it->>'owner'); end if;
    line := line || ' · 오늘';
    txt := txt || E'\n' || line;
  end loop;
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

-- 예약 실행(pg_cron): 평일 07:00 KST = UTC 일~목 22:00. 확장이 없으면(로컬 PostgreSQL·사전 검사) 건너뛴다.
-- Supabase 에서 create extension 이 거부되면 대시보드 → Database → Extensions 에서 pg_cron 을 켜고 이 파일을 한 번 더 실행하면 등록된다.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then raise notice 'pg_cron 을 만들지 못했습니다(%). 대시보드에서 켠 뒤 다시 실행하세요.', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'sail41-briefing';
    perform cron.schedule('sail41-briefing', '0 22 * * 0-4', 'select public.ictc_chat_briefing()');
    raise notice 'pg_cron 예약 등록: sail41-briefing (평일 07:00 KST)';
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
    -- 경로는 chat/<톡방id>/<난수>.<확장자> (41망) 또는 items/<schedule|tasks|personal>/<난수>.<확장자> (일정·업무 사진, v6.5) 세 단계만
    -- (화면 chatUpload · itemUpload 의 key 형식과 같아야 함). 수정·삭제 정책은 없으므로 anon 은 올린 파일을 바꾸거나 지울 수 없다
    execute $p$create policy "sail41 chat upload" on storage.objects for insert to anon, authenticated
      with check (bucket_id = 'sail41' and ((storage.foldername(name))[1] = 'chat' or (storage.foldername(name))[1] = 'items')
        and name ~ '^(chat/[A-Za-z0-9_.%-]{1,64}|items/(schedule|tasks|personal))/[A-Za-z0-9_.-]{1,80}$')$p$;
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
    if f.name in ('ictc_fail_delay', 'ictc_check_pin', 'ictc_check_view_pin', 'ictc_user_check', 'ictc_require_view', 'ictc_require_edit', 'ictc_trash', 'ictc_chat_check', 'ictc_check_item', 'ictc_dt', 'ictc_briefing_text', 'ictc_chat_briefing') then
      execute format('revoke all on function %s from anon, authenticated', f.sig);   -- 내부 전용
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
