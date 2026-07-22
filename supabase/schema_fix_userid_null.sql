-- FIX: "null value in column user_id of relation stores"
-- Run once in Supabase → SQL → New query → Run.
-- Safe to re-run.

-- Drop Auth FKs so placeholder user_id is allowed.
alter table public.products drop constraint if exists products_user_id_fkey;
alter table public.stores drop constraint if exists stores_user_id_fkey;
alter table public.deletion_log drop constraint if exists deletion_log_user_id_fkey;
alter table public.staff_users drop constraint if exists staff_users_user_id_fkey;

-- Ensure shop_id exists and is filled.
alter table public.products add column if not exists shop_id text;
alter table public.stores add column if not exists shop_id text;
alter table public.deletion_log add column if not exists shop_id text;
alter table public.staff_users add column if not exists shop_id text;

update public.products set shop_id = 'expiry-check-shop' where shop_id is null;
update public.stores set shop_id = 'expiry-check-shop' where shop_id is null;
update public.deletion_log set shop_id = 'expiry-check-shop' where shop_id is null;
update public.staff_users set shop_id = 'expiry-check-shop' where shop_id is null;

alter table public.products alter column shop_id set default 'expiry-check-shop';
alter table public.stores alter column shop_id set default 'expiry-check-shop';
alter table public.deletion_log alter column shop_id set default 'expiry-check-shop';
alter table public.staff_users alter column shop_id set default 'expiry-check-shop';

alter table public.products alter column shop_id set not null;
alter table public.stores alter column shop_id set not null;
alter table public.deletion_log alter column shop_id set not null;
alter table public.staff_users alter column shop_id set not null;

-- Placeholder Auth UUID used by the app when user_id is still required.
-- 00000000-0000-4000-8000-000000000001
alter table public.products
  alter column user_id set default '00000000-0000-4000-8000-000000000001';
alter table public.stores
  alter column user_id set default '00000000-0000-4000-8000-000000000001';
alter table public.deletion_log
  alter column user_id set default '00000000-0000-4000-8000-000000000001';
alter table public.staff_users
  alter column user_id set default '00000000-0000-4000-8000-000000000001';

update public.products
  set user_id = '00000000-0000-4000-8000-000000000001'
  where user_id is null;
update public.stores
  set user_id = '00000000-0000-4000-8000-000000000001'
  where user_id is null;
update public.deletion_log
  set user_id = '00000000-0000-4000-8000-000000000001'
  where user_id is null;
update public.staff_users
  set user_id = '00000000-0000-4000-8000-000000000001'
  where user_id is null;

-- Prefer nullable user_id (shop_id is the real scope). Ignore if PK blocks it.
do $$ begin
  alter table public.products alter column user_id drop not null;
exception when others then raise notice 'products.user_id: %', sqlerrm;
end $$;
do $$ begin
  -- stores PK may still be (user_id, store_id) — switch first.
  alter table public.stores drop constraint if exists stores_pkey;
  alter table public.stores alter column user_id drop not null;
  alter table public.stores add primary key (shop_id, store_id);
exception when others then raise notice 'stores PK/user_id: %', sqlerrm;
end $$;
do $$ begin
  alter table public.deletion_log alter column user_id drop not null;
exception when others then raise notice 'deletion_log.user_id: %', sqlerrm;
end $$;
do $$ begin
  alter table public.staff_users drop constraint if exists staff_users_pkey;
  alter table public.staff_users alter column user_id drop not null;
  alter table public.staff_users add primary key (shop_id, username);
exception when others then raise notice 'staff_users PK/user_id: %', sqlerrm;
end $$;

-- Shop-scoped RLS (anon key).
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
