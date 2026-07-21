-- Expiry Check — Supabase schema for live multi-device sync
-- Run this in the Supabase SQL Editor (Project → SQL → New query).
-- Then enable Replication for `products` (Database → Replication → supabase_realtime).

-- Products (stable UUID identity across devices)
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
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

create index if not exists products_user_updated_idx
  on public.products (user_id, updated_at desc);

-- Store branch names (ids 1–3 match the app's local branches)
create table if not exists public.stores (
  user_id uuid not null references auth.users (id) on delete cascade,
  store_id integer not null,
  name text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, store_id)
);

-- Deletion audit log
create table if not exists public.deletion_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
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

alter table public.products enable row level security;
alter table public.stores enable row level security;
alter table public.deletion_log enable row level security;

-- Each shop sync account only sees its own rows.
create policy "products_select_own" on public.products
  for select using (auth.uid() = user_id);
create policy "products_insert_own" on public.products
  for insert with check (auth.uid() = user_id);
create policy "products_update_own" on public.products
  for update using (auth.uid() = user_id);
create policy "products_delete_own" on public.products
  for delete using (auth.uid() = user_id);

create policy "stores_select_own" on public.stores
  for select using (auth.uid() = user_id);
create policy "stores_insert_own" on public.stores
  for insert with check (auth.uid() = user_id);
create policy "stores_update_own" on public.stores
  for update using (auth.uid() = user_id);
create policy "stores_delete_own" on public.stores
  for delete using (auth.uid() = user_id);

create policy "deletion_log_select_own" on public.deletion_log
  for select using (auth.uid() = user_id);
create policy "deletion_log_insert_own" on public.deletion_log
  for insert with check (auth.uid() = user_id);

-- Realtime: add tables to the supabase_realtime publication (idempotent).
do $$
begin
  begin
    alter publication supabase_realtime add table public.products;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.stores;
  exception when duplicate_object then null;
  end;
end $$;
