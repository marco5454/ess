-- Phase 2 initial schema
-- Source of truth: docs/phase-2-schema.md
--
-- Contents:
--   * calling_state enum
--   * members, callings, calling_events tables
--   * set_updated_at trigger for members + callings
--   * permissive-auth RLS on all three tables
--
-- Design notes live in docs/phase-2-schema.md. Keep that doc and this
-- migration aligned; further changes go in new migrations, not by editing
-- this one.

-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------

-- gen_random_uuid() lives in pgcrypto. Supabase preinstalls it, but be explicit
-- so this migration also works against a fresh local db.
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- Enum: calling_state
-- -----------------------------------------------------------------------------

create type public.calling_state as enum (
  'selected',
  'extended',
  'accepted',
  'declined',
  'sustained',
  'set_apart',
  'active',
  'released'
);

-- -----------------------------------------------------------------------------
-- Helper: set_updated_at trigger function
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Table: members
-- -----------------------------------------------------------------------------

create table public.members (
  id                uuid primary key default gen_random_uuid(),
  first_name        text not null,
  last_name         text not null,
  preferred_name    text,
  phone             text,
  email             text,
  notes             text,
  date_of_birth     date,
  sex               text,
  priesthood_office text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_members_last_first on public.members (last_name, first_name);
create index idx_members_active     on public.members (is_active) where is_active = true;

create trigger trg_members_set_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Table: callings
-- -----------------------------------------------------------------------------

create table public.callings (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid not null references public.members(id) on delete restrict,
  title        text not null,
  organization text,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index idx_callings_member       on public.callings (member_id);
create index idx_callings_organization on public.callings (organization);

create trigger trg_callings_set_updated_at
  before update on public.callings
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Table: calling_events (append-only)
-- -----------------------------------------------------------------------------

create table public.calling_events (
  id          uuid primary key default gen_random_uuid(),
  calling_id  uuid not null references public.callings(id) on delete cascade,
  state       public.calling_state not null,
  occurred_at timestamptz not null,
  notes       text,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index idx_calling_events_calling_time
  on public.calling_events (calling_id, occurred_at desc, created_at desc);

create index idx_calling_events_state on public.calling_events (state);

-- -----------------------------------------------------------------------------
-- Row-Level Security
--
-- Phase 2 policy: every authenticated user (bishopric) has full access; anon
-- users have none. See docs/phase-2-schema.md for rationale.
-- -----------------------------------------------------------------------------

alter table public.members        enable row level security;
alter table public.callings       enable row level security;
alter table public.calling_events enable row level security;

create policy "authenticated_all_members"
  on public.members
  for all
  to authenticated
  using (true)
  with check (true);

create policy "authenticated_all_callings"
  on public.callings
  for all
  to authenticated
  using (true)
  with check (true);

create policy "authenticated_all_calling_events"
  on public.calling_events
  for all
  to authenticated
  using (true)
  with check (true);
