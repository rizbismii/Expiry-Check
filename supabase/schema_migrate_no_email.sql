-- MIGRATE existing Expiry Check project from email Auth → shop_id (no emails)
-- Run once in Supabase SQL Editor if you already ran the older schema.sql.
-- Safe to re-run.

-- ---- products ----
alter table public.products add column if not exists shop_id text;
update public.products set shop_id = 'expiry-check-shop' where shop_id is null;
alter table public.products alter column shop_id set default 'expiry-check-shop';
alter table public.products alter column shop_id set not null;

alter table public.products drop constraint if exists products_user_id_fkey;
do $$ begin
  alter table public.products alter column user_id drop not null;
exception when others then null;
end $$;

create index if not exists products_shop_updated_idx
  on public.products (shop_id, updated_at desc);

-- ---- stores ----
alter table public.stores add column if not exists shop_id text;
update public.stores set shop_id = 'expiry-check-shop' where shop_id is null;
alter table public.stores alter column shop_id set default 'expiry-check-shop';
alter table public.stores alter column shop_id set not null;

alter table public.stores drop constraint if exists stores_user_id_fkey;
do $$ begin
  alter table public.stores alter column user_id drop not null;
exception when others then null;
end $$;

-- Recreate primary key as (shop_id, store_id)
do $$
begin
  alter table public.stores drop constraint if exists stores_pkey;
  alter table public.stores add primary key (shop_id, store_id);
exception when others then
  raise notice 'stores PK migrate: %', sqlerrm;
end $$;

-- ---- deletion_log ----
alter table public.deletion_log add column if not exists shop_id text;
update public.deletion_log set shop_id = 'expiry-check-shop' where shop_id is null;
alter table public.deletion_log alter column shop_id set default 'expiry-check-shop';
alter table public.deletion_log alter column shop_id set not null;

alter table public.deletion_log drop constraint if exists deletion_log_user_id_fkey;
do $$ begin
  alter table public.deletion_log alter column user_id drop not null;
exception when others then null;
end $$;

-- ---- staff_users ----
alter table public.staff_users add column if not exists shop_id text;
update public.staff_users set shop_id = 'expiry-check-shop' where shop_id is null;
alter table public.staff_users alter column shop_id set default 'expiry-check-shop';
alter table public.staff_users alter column shop_id set not null;

alter table public.staff_users drop constraint if exists staff_users_user_id_fkey;
do $$ begin
  alter table public.staff_users alter column user_id drop not null;
exception when others then null;
end $$;

do $$
begin
  alter table public.staff_users drop constraint if exists staff_users_pkey;
  alter table public.staff_users add primary key (shop_id, username);
exception when others then
  raise notice 'staff_users PK migrate: %', sqlerrm;
end $$;

-- ---- RLS: drop auth.uid policies, add shop_id policies ----
drop policy if exists "products_select_own" on public.products;
drop policy if exists "products_insert_own" on public.products;
drop policy if exists "products_update_own" on public.products;
drop policy if exists "products_delete_own" on public.products;
drop policy if exists "products_shop_all" on public.products;
create policy "products_shop_all" on public.products
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

drop policy if exists "stores_select_own" on public.stores;
drop policy if exists "stores_insert_own" on public.stores;
drop policy if exists "stores_update_own" on public.stores;
drop policy if exists "stores_delete_own" on public.stores;
drop policy if exists "stores_shop_all" on public.stores;
create policy "stores_shop_all" on public.stores
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

drop policy if exists "deletion_log_select_own" on public.deletion_log;
drop policy if exists "deletion_log_insert_own" on public.deletion_log;
drop policy if exists "deletion_log_shop_all" on public.deletion_log;
create policy "deletion_log_shop_all" on public.deletion_log
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

drop policy if exists "staff_users_select_own" on public.staff_users;
drop policy if exists "staff_users_insert_own" on public.staff_users;
drop policy if exists "staff_users_update_own" on public.staff_users;
drop policy if exists "staff_users_delete_own" on public.staff_users;
drop policy if exists "staff_users_shop_all" on public.staff_users;
create policy "staff_users_shop_all" on public.staff_users
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

alter table public.products replica identity full;
alter table public.stores replica identity full;
alter table public.staff_users replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'products'
  ) then
    execute 'alter publication supabase_realtime add table public.products';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'stores'
  ) then
    execute 'alter publication supabase_realtime add table public.stores';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'staff_users'
  ) then
    execute 'alter publication supabase_realtime add table public.staff_users';
  end if;
exception when others then
  raise notice 'Realtime publication step skipped: %', sqlerrm;
end $$;
