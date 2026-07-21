-- Additive migration: run this if you already applied an older schema.sql
-- without staff_users. Safe to re-run.

create table if not exists public.staff_users (
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  password text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, username)
);

alter table public.staff_users enable row level security;

drop policy if exists "staff_users_select_own" on public.staff_users;
drop policy if exists "staff_users_insert_own" on public.staff_users;
drop policy if exists "staff_users_update_own" on public.staff_users;
drop policy if exists "staff_users_delete_own" on public.staff_users;
create policy "staff_users_select_own" on public.staff_users
  for select using (auth.uid() = user_id);
create policy "staff_users_insert_own" on public.staff_users
  for insert with check (auth.uid() = user_id);
create policy "staff_users_update_own" on public.staff_users
  for update using (auth.uid() = user_id);
create policy "staff_users_delete_own" on public.staff_users
  for delete using (auth.uid() = user_id);

alter table public.staff_users replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'staff_users'
  ) then
    execute 'alter publication supabase_realtime add table public.staff_users';
  end if;
exception
  when others then
    raise notice 'Realtime publication step skipped: %', sqlerrm;
end $$;
