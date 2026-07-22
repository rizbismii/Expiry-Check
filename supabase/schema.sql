-- Expiry Check — Supabase schema for live multi-device sync (NO email auth)
-- Run this whole file once in: Project → SQL → New query → Run.
-- Safe to re-run (idempotent).
--
-- Phones connect with the anon/publishable key only. No Auth users, no emails.
-- Staff logins created in the app (Manage users) sync via staff_users.

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id text not null default 'expiry-check-shop',
  store_id integer not null default 1,
  name text not null,
  brand text not null default '',
  barcode_id text not null default '',
  batch text not null default '',
  category text not null default 'General',
  quantity integer not null default 1,
  prod_date timestamptz,
  expiry_date timestamptz not null,
  added_date timestamptz not null,
  notes text not null default '',
  created_by text not null default '',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists products_shop_updated_idx
  on public.products (shop_id, updated_at desc);

create table if not exists public.stores (
  shop_id text not null default 'expiry-check-shop',
  store_id integer not null,
  name text not null,
  updated_at timestamptz not null default now(),
  primary key (shop_id, store_id)
);

create table if not exists public.deletion_log (
  id uuid primary key default gen_random_uuid(),
  shop_id text not null default 'expiry-check-shop',
  deleted_at timestamptz not null default now(),
  deleted_by text not null default '',
  note text not null default '',
  store_id integer not null default 1,
  name text not null,
  brand text not null default '',
  batch text not null default '',
  expiry_date timestamptz not null,
  quantity integer not null default 1
);

create table if not exists public.staff_users (
  shop_id text not null default 'expiry-check-shop',
  username text not null,
  password text not null,
  updated_at timestamptz not null default now(),
  primary key (shop_id, username)
);

alter table public.products enable row level security;
alter table public.stores enable row level security;
alter table public.deletion_log enable row level security;
alter table public.staff_users enable row level security;

-- Shared-shop policies (anon key in the app). Same trust model as a baked-in
-- sync password, without sending any Auth emails.
drop policy if exists "products_shop_all" on public.products;
drop policy if exists "products_select_own" on public.products;
drop policy if exists "products_insert_own" on public.products;
drop policy if exists "products_update_own" on public.products;
drop policy if exists "products_delete_own" on public.products;
create policy "products_shop_all" on public.products
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

drop policy if exists "stores_shop_all" on public.stores;
drop policy if exists "stores_select_own" on public.stores;
drop policy if exists "stores_insert_own" on public.stores;
drop policy if exists "stores_update_own" on public.stores;
drop policy if exists "stores_delete_own" on public.stores;
create policy "stores_shop_all" on public.stores
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

drop policy if exists "deletion_log_shop_all" on public.deletion_log;
drop policy if exists "deletion_log_select_own" on public.deletion_log;
drop policy if exists "deletion_log_insert_own" on public.deletion_log;
create policy "deletion_log_shop_all" on public.deletion_log
  for all using (shop_id = 'expiry-check-shop')
  with check (shop_id = 'expiry-check-shop');

drop policy if exists "staff_users_shop_all" on public.staff_users;
drop policy if exists "staff_users_select_own" on public.staff_users;
drop policy if exists "staff_users_insert_own" on public.staff_users;
drop policy if exists "staff_users_update_own" on public.staff_users;
drop policy if exists "staff_users_delete_own" on public.staff_users;
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
      and schemaname = 'public'
      and tablename = 'products'
  ) then
    execute 'alter publication supabase_realtime add table public.products';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'stores'
  ) then
    execute 'alter publication supabase_realtime add table public.stores';
  end if;

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
