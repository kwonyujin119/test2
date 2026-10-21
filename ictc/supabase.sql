-- ICTC 일정·업무 보드용 Supabase 설정
-- Supabase 대시보드 → SQL Editor → New query 에 전체를 붙여넣고 Run 하세요.
-- ★ 아래 '1234' 를 팀 편집 PIN으로 바꾼 뒤 실행하세요. (숫자/문자 모두 가능)

create table if not exists public.ictc_items (
  id          text primary key,
  kind        text not null check (kind in ('schedule', 'tasks')),
  data        jsonb not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.ictc_settings (
  key   text primary key,
  value text not null
);

insert into public.ictc_settings (key, value) values ('edit_pin', '1234')
on conflict (key) do update set value = excluded.value;

-- 읽기: 누구나 / 쓰기: PIN 검증을 거친 함수로만
alter table public.ictc_items    enable row level security;
alter table public.ictc_settings enable row level security;

drop policy if exists "ictc public read" on public.ictc_items;
create policy "ictc public read" on public.ictc_items for select to anon, authenticated using (true);
-- ictc_settings 에는 정책이 없으므로 anon 은 PIN을 읽을 수 없습니다.

create or replace function public.ictc_check_pin(p_pin text)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.ictc_settings where key = 'edit_pin' and value = p_pin);
$$;

create or replace function public.ictc_save(p_pin text, p_kind text, p_item jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.ictc_check_pin(p_pin) then raise exception 'PIN_INVALID'; end if;
  if coalesce(p_item->>'id', '') = '' then raise exception 'ID_REQUIRED'; end if;
  insert into public.ictc_items (id, kind, data, updated_at)
  values (p_item->>'id', p_kind, p_item, now())
  on conflict (id) do update set data = excluded.data, kind = excluded.kind, updated_at = now();
end $$;

create or replace function public.ictc_delete(p_pin text, p_kind text, p_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.ictc_check_pin(p_pin) then raise exception 'PIN_INVALID'; end if;
  delete from public.ictc_items where id = p_id and kind = p_kind;
end $$;

-- JSON 가져오기(전체 교체)용
create or replace function public.ictc_replace(p_pin text, p_kind text, p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.ictc_check_pin(p_pin) then raise exception 'PIN_INVALID'; end if;
  delete from public.ictc_items where kind = p_kind;
  insert into public.ictc_items (id, kind, data, updated_at)
  select coalesce(x->>'id', gen_random_uuid()::text), p_kind, x, now()
  from jsonb_array_elements(p_items) as x;
end $$;

-- PIN 변경: select ictc_set_pin('기존PIN', '새PIN');
create or replace function public.ictc_set_pin(p_old text, p_new text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.ictc_check_pin(p_old) then raise exception 'PIN_INVALID'; end if;
  if length(coalesce(p_new, '')) < 4 then raise exception 'PIN_TOO_SHORT'; end if;
  update public.ictc_settings set value = p_new where key = 'edit_pin';
end $$;

revoke all on function public.ictc_check_pin(text) from public;
revoke all on function public.ictc_save(text, text, jsonb) from public;
revoke all on function public.ictc_delete(text, text, text) from public;
revoke all on function public.ictc_replace(text, text, jsonb) from public;
revoke all on function public.ictc_set_pin(text, text) from public;
grant execute on function public.ictc_check_pin(text) to anon, authenticated;
grant execute on function public.ictc_save(text, text, jsonb) to anon, authenticated;
grant execute on function public.ictc_delete(text, text, text) to anon, authenticated;
grant execute on function public.ictc_replace(text, text, jsonb) to anon, authenticated;
grant execute on function public.ictc_set_pin(text, text) to anon, authenticated;
