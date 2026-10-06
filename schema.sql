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
-- (mn_strains, mn_units and the Batch/Block ID triggers are near the end)

create table if not exists mn_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  kind text not null default 'fruiting'
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
-- mn_rooms.kind: 'fruiting' (default - every room that existed before this
-- column did is a fruiting room) or 'incubation' (the incubation shelf map).
alter table mn_rooms add column if not exists kind text not null default 'fruiting';
-- mn_costs.species needs to be unique for the app's upsert(...,{onConflict:
-- "species"}) calls to work at all (Postgres's ON CONFLICT requires a real
-- unique or exclusion constraint on the named column, or it errors outright
-- - see the commit that first added this). A unique INDEX enforces exactly
-- the same guarantee ON CONFLICT needs, and unlike a table-level UNIQUE
-- constraint declared inline in `create table`, `create unique index if
-- not exists` genuinely reaches a table that already exists.
create unique index if not exists mn_costs_species_key on mn_costs (species);

-- ================= BATCH IDs, BLOCK IDs & STRAINS (2026-10) =================
-- Batch ID  = AADDD-LL     e.g. 26279-02 (sown 6 Oct 2026, 2nd batch that day)
-- Block ID  = AADDD-LL-BB  e.g. 26279-02-17 (block 17 of that batch)
--   AA  = 2-digit year of the inoculation (sowing) date
--   DDD = day of the year (Julian day, 001-366)
--   LL  = batch number within that day, 01-99
--   BB  = block number within the batch, 01-99 (3 digits only for old
--         batches that already had more than 99 blocks)
-- The database assigns both - never the browser - so two people creating
-- batches at the same moment can't get the same ID. Once assigned, a Batch
-- ID never changes (correcting the inoculation date later keeps it), and
-- block numbers are never reused.

-- mn_strains: the "ID Cepa" list (strain code -> species/variety/supplier).
-- Edit it from the app (Settings -> Strains) or straight in this table.
create table if not exists mn_strains (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  species text not null,
  variety text,
  supplier text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table mn_batches add column if not exists batch_seq integer;
alter table mn_batches add column if not exists batch_code text;
alter table mn_batches add column if not exists strain_code text references mn_strains(code) on update cascade;
create unique index if not exists mn_batches_batch_code_key on mn_batches (batch_code);
create index if not exists idx_mn_batches_strain_code on mn_batches(strain_code);

-- mn_units: one row per physical block, numbered within its batch.
create table if not exists mn_units (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references mn_batches(id) on delete cascade,
  unit_no integer not null,
  unit_code text not null unique,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (batch_id, unit_no)
);
create index if not exists idx_mn_units_batch_id on mn_units(batch_id);

-- which block (scanned) sits in a shelf slot
alter table mn_placements add column if not exists unit_id uuid references mn_units(id) on delete set null;
alter table mn_placements add column if not exists unit_code text;
create index if not exists idx_mn_placements_unit_id on mn_placements(unit_id);

do $$
declare
  t text;
begin
  foreach t in array array['mn_strains','mn_units']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "authenticated_full_access" on %I', t);
    execute format(
      'create policy "authenticated_full_access" on %I for all to authenticated using (true) with check (true)',
      t
    );
  end loop;
end $$;

create or replace function mn_fmt_seq(n integer) returns text
language sql immutable as $$
  select case when n < 100 then lpad(n::text, 2, '0') else n::text end
$$;

-- New batch: assign batch_no (kept for old QR labels), the per-day
-- sequence and the Batch ID. One lock serialises concurrent creates.
create or replace function mn_batch_before_insert() returns trigger
language plpgsql as $$
begin
  perform pg_advisory_xact_lock(hashtext('mn_batches_code'));
  new.batch_no := coalesce((select max(batch_no) from mn_batches), 0) + 1;
  new.batch_seq := coalesce((select max(batch_seq) from mn_batches where inoc_date = new.inoc_date), 0) + 1;
  if new.batch_seq > 99 then
    raise exception 'There are already 99 batches sown on % (the per-day maximum)', new.inoc_date;
  end if;
  new.batch_code := to_char(new.inoc_date, 'YY') || to_char(new.inoc_date, 'DDD') || '-' || mn_fmt_seq(new.batch_seq);
  return new;
end $$;

-- IDs are fixed once assigned, even if the batch details are corrected.
create or replace function mn_batch_before_update() returns trigger
language plpgsql as $$
begin
  new.batch_no := old.batch_no;
  if old.batch_code is not null then
    new.batch_code := old.batch_code;
    new.batch_seq := old.batch_seq;
  end if;
  return new;
end $$;

-- Keep one active block row per block in the batch: adding blocks creates
-- the next numbers, removing blocks voids the highest unplaced ones.
-- Numbers are never reused.
create or replace function mn_sync_units(p_batch uuid) returns void
language plpgsql as $$
declare
  b mn_batches%rowtype;
  n_active integer;
  last_no integer;
begin
  select * into b from mn_batches where id = p_batch;
  if b.id is null or b.batch_code is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('mn_units:' || p_batch::text));
  select count(*) filter (where voided_at is null), coalesce(max(unit_no), 0)
    into n_active, last_no from mn_units where batch_id = p_batch;
  if b.blocks_total > n_active then
    insert into mn_units (batch_id, unit_no, unit_code)
      select p_batch, n, b.batch_code || '-' || mn_fmt_seq(n)
      from generate_series(last_no + 1, last_no + (b.blocks_total - n_active)) n;
  elsif b.blocks_total < n_active then
    update mn_units set voided_at = now() where id in (
      select u.id from mn_units u
      where u.batch_id = p_batch and u.voided_at is null
      order by exists (select 1 from mn_placements p where p.unit_id = u.id and p.removed_date is null), u.unit_no desc
      limit n_active - b.blocks_total);
  end if;
end $$;

create or replace function mn_batch_after_write() returns trigger
language plpgsql as $$
begin
  perform mn_sync_units(new.id);
  return null;
end $$;

drop trigger if exists mn_batches_assign_code on mn_batches;
create trigger mn_batches_assign_code before insert on mn_batches
  for each row execute function mn_batch_before_insert();
drop trigger if exists mn_batches_lock_code on mn_batches;
create trigger mn_batches_lock_code before update on mn_batches
  for each row execute function mn_batch_before_update();
drop trigger if exists mn_batches_sync_units on mn_batches;
create trigger mn_batches_sync_units after insert or update of blocks_total, batch_code on mn_batches
  for each row execute function mn_batch_after_write();

-- Give batches created before this existed a Batch ID from their current
-- inoculation date (in creation order within each day). Setting batch_code
-- also creates their block rows via the trigger above. Does nothing for
-- batches that already have one.
with base as (
  select inoc_date, max(batch_seq) as mx from mn_batches where batch_seq is not null group by inoc_date
), ranked as (
  select b.id, b.inoc_date,
    (row_number() over (partition by b.inoc_date order by b.created_at, b.batch_no) + coalesce(base.mx, 0))::integer as seq
  from mn_batches b left join base on base.inoc_date = b.inoc_date
  where b.batch_code is null
)
update mn_batches b
  set batch_seq = r.seq,
      batch_code = to_char(r.inoc_date, 'YY') || to_char(r.inoc_date, 'DDD') || '-' || mn_fmt_seq(r.seq)
from ranked r
where b.id = r.id;

-- Starting strain list. Only adds codes that aren't there yet, so edits
-- made in the app are never overwritten by re-running this file.
insert into mn_strains (code, species, variety, supplier) values
  ('PCSK', 'Psilocybe cubensis', 'Shakti', 'Hongos del vecino'),
  ('PCHB', 'Psilocybe cubensis', 'Hillbilly', 'Hongos del vecino'),
  ('PCGT', 'Psilocybe cubensis', 'Golden teacher', 'Suplihongos'),
  ('PCBV', 'Psilocybe cubensis', 'Bluey Vuitton', 'Hongos del vecino'),
  ('PCCB', 'Psilocybe cubensis', 'Melmac', 'Indigo'),
  ('HELB', 'Hericium erinaceus', 'MM', 'Cultura Fungi'),
  ('BOCF', 'Pleorotus ostreatus', 'BO', 'Cultura fungí'),
  ('POSO', 'Pleurotus ostreatus', 'Summer oyster', 'Ryan'),
  ('PDRY', 'Pleurotus djamour', 'Sakura', 'Ryan'),
  ('LECF', 'Lentinula edobes', '5000', 'Cultura fungi'),
  ('BPKO', 'Pleorotus ostreatus', 'Hybrid', 'Cultura fungi'),
  ('GSBR', 'Ganoderma sianeses', 'Black reishi', 'Spore n sprout'),
  ('GMAR', 'Ganoderma multiporium', 'Antler reishi', 'Spore n sprout'),
  ('CMSS', 'Cordyceps militaris', null, 'Spore n sprout'),
  ('CMAL', 'Cordyceps militaris', 'Albino', 'Spore n sprout'),
  ('CMCV', 'Cordyceps militaris', 'Campo Verde', 'Hifa x Hifa'),
  ('FVGE', 'Flammulina velutipes', 'Golden enoki', 'colombia'),
  ('TSCV', 'Trametes sanguineus', 'Campo Verde', 'Hifa x Hifa'),
  ('PPSO', 'Pleurotus pulmonaris', 'Summer oyster', 'Ryan'),
  ('PSSV', 'Psilocybe subtropicalis', null, 'Ryan'),
  ('PCSM', 'Psilocybe cubensis', 'Steel magnolia', 'Ryan'),
  ('PCMM', 'Psilocybe cubensis', 'Melmac OG', 'Ryan'),
  ('PCCV', 'Psilocybe cubensis', 'Campo Verde', 'Ryan')
on conflict (code) do nothing;
