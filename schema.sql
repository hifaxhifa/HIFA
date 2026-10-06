-- Batch Tracker - schema.sql
-- Full schema for a fresh Supabase project: tables, indexes, and RLS.
-- Safe to re-run: every statement is guarded (IF NOT EXISTS / DROP POLICY IF EXISTS)
-- so running this twice on the same project won't error or duplicate anything.
--
-- This is applied automatically by `setup.js` against your own project's
-- Postgres connection. You can also just paste this whole file into the
-- Supabase SQL Editor (Dashboard -> SQL Editor -> New query -> Run) if you'd
-- rather not run the setup script at all.

create extension if not exists pgcrypto;

-- ================= TABLES =================
-- Hierarchy: mn_rooms -> mn_zones -> mn_bays -> mn_placements -> mn_batches

create table if not exists mn_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists mn_zones (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references mn_rooms(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  block_kg numeric,
  created_at timestamptz not null default now()
);

create table if not exists mn_bays (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references mn_zones(id) on delete cascade,
  bay_no integer not null,
  rows integer not null default 9,
  slots_per_row integer not null default 6,
  slots_per_line integer,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists mn_batches (
  id uuid primary key default gen_random_uuid(),
  batch_no integer not null,
  name text not null,
  species text not null,
  scientific text,
  substrate text,
  method text,
  spawn_code text,
  inoc_date date not null,
  blocks_total integer not null default 0,
  notes text,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  block_sizes jsonb,
  ready_date date
);

create table if not exists mn_batch_notes (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references mn_batches(id) on delete cascade,
  note_date date not null default current_date,
  note text not null,
  created_at timestamptz not null default now()
);

create table if not exists mn_harvests (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references mn_batches(id) on delete cascade,
  harvest_date date not null,
  weight_g numeric not null,
  flush integer,
  note text,
  created_at timestamptz not null default now(),
  slot_code text
);

create table if not exists mn_movements (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references mn_batches(id) on delete cascade,
  move_date date not null,
  from_state text not null,
  to_state text not null,
  count integer not null,
  note text,
  created_at timestamptz not null default now(),
  kg numeric
);

create table if not exists mn_placements (
  id uuid primary key default gen_random_uuid(),
  bay_id uuid not null references mn_bays(id) on delete cascade,
  slot_code text not null,
  row_letter text not null,
  slot_num integer not null,
  batch_id uuid references mn_batches(id) on delete set null,
  placed_date date not null,
  removed_date date,
  created_at timestamptz not null default now(),
  removed_note text
);

create table if not exists mn_costs (
  id uuid primary key default gen_random_uuid(),
  species text not null,
  substrate_cost numeric not null default 0,
  spawn_cost numeric not null default 0,
  bag_cost numeric not null default 0,
  other_cost numeric not null default 0,
  sale_price_kg numeric,
  note text,
  updated_at timestamptz not null default now(),
  retail_price_kg numeric,
  packed_price_block numeric
);

create table if not exists mn_settings (
  key text primary key,
  value text
);

create table if not exists mn_yield_defaults (
  species text primary key,
  yield_kg_per_block_low numeric not null default 0,
  yield_kg_per_block_high numeric not null default 0,
  days_to_first_flush integer,
  notes text,
  updated_at timestamptz not null default now(),
  days_to_harvest_low integer,
  days_to_harvest_high integer
);

-- ================= INDEXES =================
-- Postgres does not auto-index foreign key columns; add them for join/filter performance.

create index if not exists idx_mn_zones_room_id on mn_zones(room_id);
create index if not exists idx_mn_bays_zone_id on mn_bays(zone_id);
create index if not exists idx_mn_batch_notes_batch_id on mn_batch_notes(batch_id);
create index if not exists idx_mn_harvests_batch_id on mn_harvests(batch_id);
create index if not exists idx_mn_movements_batch_id on mn_movements(batch_id);
create index if not exists idx_mn_placements_bay_id on mn_placements(bay_id);
create index if not exists idx_mn_placements_batch_id on mn_placements(batch_id);

-- ================= ROW LEVEL SECURITY =================
-- Standard single-tenant policy: any logged-in (authenticated) user of YOUR
-- Supabase project has full read/write access to all of this app's tables.
-- This app has no per-user data separation within one farm - everyone who
-- signs in is staff of the same farm and should see/edit the same data.
-- You create logins for your own staff manually via the Supabase dashboard
-- (Authentication -> Users -> Add user); nobody outside your project can
-- reach this data since the anon key alone (no valid session) is refused
-- by these policies.

do $$
declare
  t text;
begin
  foreach t in array array[
    'mn_rooms','mn_zones','mn_bays','mn_batches','mn_batch_notes',
    'mn_harvests','mn_movements','mn_placements','mn_costs',
    'mn_settings','mn_yield_defaults'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "authenticated_full_access" on %I', t);
    execute format(
      'create policy "authenticated_full_access" on %I for all to authenticated using (true) with check (true)',
      t
    );
  end loop;
end $$;

-- ================= KEEPING AN EXISTING PROJECT UP TO DATE =================
-- setup.js/setup.html both promise "schema.sql is safe to re-run" as the
-- standard way to pick up anything added after your first setup. That's
-- true for brand-new tables/columns/indexes ABOVE this line (every
-- `create table` up there is `if not exists`, so it does nothing - safely
-- - on a database that already has that table). It was NOT true for a
-- column or constraint added to a table that already existed: `create
-- table if not exists mn_costs (... unique ...)` silently does nothing at
-- all to a database that already has mn_costs, new column and all -
-- re-running schema.sql looked successful (no error) but genuinely didn't
-- add the new column. Found 2026-09-25 while adding packed_price_block.
--
-- Anything that needs to reach an EXISTING table goes below instead, using
-- a form Postgres actually supports re-running against one that's already
-- caught up (`add column if not exists`, `create index if not exists`) -
-- this is what makes "just re-run schema.sql" a real, working answer for
-- an existing install, not just a fresh one.
alter table mn_costs add column if not exists packed_price_block numeric;
-- mn_costs.species needs to be unique for the app's upsert(...,{onConflict:
-- "species"}) calls to work at all (Postgres's ON CONFLICT requires a real
-- unique or exclusion constraint on the named column, or it errors outright
-- - see the commit that first added this). A unique INDEX enforces exactly
-- the same guarantee ON CONFLICT needs, and unlike a table-level UNIQUE
-- constraint declared inline in `create table`, `create unique index if
-- not exists` genuinely reaches a table that already exists.
create unique index if not exists mn_costs_species_key on mn_costs (species);
