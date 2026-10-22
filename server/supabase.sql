-- ============================================================
-- 지휘역량강화센터 일정·업무 보드 - Supabase 설정 (v2)
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
alter table public.ictc_items add constraint ictc_items_kind_check check (kind in ('schedule', 'tasks', 'personal'));
drop index if exists public.ictc_items_kind_board_idx;
create index if not exists ictc_items_kind_board_updated_idx on public.ictc_items (kind, board, updated_at desc);


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
returns void language sql security definer as $$ select pg_sleep(0.8); $$;

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

-- ---------- 공용 항목 ----------
create or replace function public.ictc_list(p_pin text, p_kind text, p_board text default 'main')
returns table (data jsonb, updated_at timestamptz) language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;
  return query select i.data, i.updated_at from public.ictc_items i
    where i.kind = p_kind and i.board = coalesce(p_board, 'main') order by i.updated_at desc;
end $$;

-- 일정·주요업무의 추가·수정·삭제는 조회 PIN 을 아는 직원 누구나 가능 (편집 PIN 은 관리 작업 전용)
create or replace function public.ictc_save(p_pin text, p_kind text, p_item jsonb, p_board text default 'main')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;
  if coalesce(p_item->>'id', '') = '' then raise exception 'ID_REQUIRED'; end if;
  insert into public.ictc_items (id, kind, board, data, updated_at)
  values (p_item->>'id', p_kind, coalesce(p_board, 'main'), p_item, now())
  on conflict (id) do update set data = excluded.data, kind = excluded.kind, board = excluded.board, updated_at = now();
end $$;

create or replace function public.ictc_delete(p_pin text, p_kind text, p_id text, p_board text default 'main')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_view(p_pin);
  delete from public.ictc_items where id = p_id and kind = p_kind and board = coalesce(p_board, 'main');
end $$;

create or replace function public.ictc_replace(p_pin text, p_kind text, p_items jsonb, p_board text default 'main')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if p_kind not in ('schedule', 'tasks') then raise exception 'KIND_INVALID'; end if;
  delete from public.ictc_items where kind = p_kind and board = coalesce(p_board, 'main');
  insert into public.ictc_items (id, kind, board, data, updated_at)
  select coalesce(x->>'id', gen_random_uuid()::text), p_kind, coalesce(p_board, 'main'), x, now()
  from jsonb_array_elements(p_items) as x;
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
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'NAME_REQUIRED'; end if;
  if exists (select 1 from public.ictc_boards where id = p_id) then raise exception 'BOARD_EXISTS'; end if;
  insert into public.ictc_boards (id, name) values (p_id, trim(p_name));
end $$;

create or replace function public.ictc_board_rename(p_pin text, p_id text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'NAME_REQUIRED'; end if;
  update public.ictc_boards set name = trim(p_name) where id = p_id;
end $$;

create or replace function public.ictc_board_delete(p_pin text, p_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_pin);
  if p_id = 'main' then raise exception 'BOARD_PROTECTED'; end if;
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
  if length(coalesce(p_id, '')) < 4 then raise exception 'USER_ID_INVALID'; end if;
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'NAME_REQUIRED'; end if;
  if length(trim(coalesce(p_pin, ''))) < 2 then raise exception 'PIN_TOO_SHORT'; end if;
  if exists (select 1 from public.ictc_users where id = p_id) then raise exception 'USER_EXISTS'; end if;
  insert into public.ictc_users (id, name, pin_hash) values (p_id, trim(p_name), crypt(p_pin, gen_salt('bf')));
  return trim(p_name);
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
  if length(trim(coalesce(p_new, ''))) < 2 then raise exception 'PIN_TOO_SHORT'; end if;
  update public.ictc_users set pin_hash = crypt(p_new, gen_salt('bf')) where id = p_id;
end $$;

-- 개인업무 이름 정정 (개인업무는 뒤4자리 + 이름으로 로그인하므로 이름이 곧 확인값). 담당자가 편집 PIN으로 실행
create or replace function public.ictc_user_reset_pin(p_edit_pin text, p_id text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_require_edit(p_edit_pin);
  if length(trim(coalesce(p_new, ''))) < 2 then raise exception 'PIN_TOO_SHORT'; end if;
  update public.ictc_users set pin_hash = crypt(p_new, gen_salt('bf')), name = p_new where id = p_id;
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
  if coalesce(p_item->>'id', '') = '' then raise exception 'ID_REQUIRED'; end if;
  insert into public.ictc_items (id, kind, board, data, updated_at)
  values (p_item->>'id', 'personal', p_id, p_item, now())
  on conflict (id) do update set data = excluded.data, updated_at = now()
  where public.ictc_items.kind = 'personal' and public.ictc_items.board = p_id;
end $$;

create or replace function public.ictc_personal_delete(p_id text, p_pin text, p_item_id text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.ictc_user_check(p_id, p_pin);
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
  delete from public.ictc_items where kind = 'personal' and board = p_id;
  delete from public.ictc_users where id = p_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
end $$;

-- ---------- 관리 ----------
-- 편집 PIN 변경: select ictc_set_pin('기존편집PIN', '새편집PIN');
-- 조회 PIN 변경: select ictc_set_view_pin('편집PIN', '새조회PIN');   ('' 이면 누구나 조회)
-- 개인업무 이름 정정: select ictc_user_reset_pin('편집PIN', '뒤4자리', '바른이름');  (개인업무는 뒤4자리 + 이름으로 로그인)
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

-- ---------- 권한 ----------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname as name from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'ictc\_%' loop
    execute format('revoke all on function %s from public', f.sig);
    if f.name in ('ictc_fail_delay', 'ictc_check_pin', 'ictc_check_view_pin', 'ictc_user_check', 'ictc_require_view', 'ictc_require_edit') then
      execute format('revoke all on function %s from anon, authenticated', f.sig);   -- 내부 전용
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
