-- Phase 3 offline-first prep: soft-delete + full sync watermarks.
--
-- The mobile app is moving to a local-first architecture (SQLite via Drift)
-- with an outbox that replays writes when the device gets back online. That
-- pattern needs two things from the server that we don't have yet:
--
--   1. `deleted_at` columns so the client can learn about deletions without
--      needing to see the row disappear at the exact moment it's connected.
--      Reads are then filtered `where deleted_at is null`. Hard deletes are
--      no longer used by the app.
--
--   2. `updated_at` on `calling_events` (it currently has only `created_at`)
--      so the client can pull deltas with a single "give me rows changed
--      since X" query per table. `members` and `callings` already have this
--      column plus the shared `set_updated_at()` trigger.
--
-- We do NOT rewrite existing hard-delete grants; the client just stops
-- calling DELETE. Keeping DELETE working is useful for admin cleanup via
-- the SQL editor.

-- -----------------------------------------------------------------------------
-- callings.deleted_at
-- -----------------------------------------------------------------------------

alter table public.callings
  add column if not exists deleted_at timestamptz;

create index if not exists idx_callings_not_deleted
  on public.callings (id)
  where deleted_at is null;

-- -----------------------------------------------------------------------------
-- calling_events.deleted_at + updated_at
-- -----------------------------------------------------------------------------
--
-- calling_events was designed append-only, so it never had `updated_at`. For
-- soft deletes to survive a delta sync, we need to bump a timestamp when a
-- row's deletion flips. We reuse the shared set_updated_at() trigger, which
-- means `updated_at` will also bump if any other column is ever updated
-- (currently the app never updates events, only inserts and deletes them).

alter table public.calling_events
  add column if not exists updated_at timestamptz not null default now();

alter table public.calling_events
  add column if not exists deleted_at timestamptz;

create index if not exists idx_calling_events_not_deleted
  on public.calling_events (id)
  where deleted_at is null;

drop trigger if exists trg_calling_events_set_updated_at on public.calling_events;
create trigger trg_calling_events_set_updated_at
  before update on public.calling_events
  for each row execute function public.set_updated_at();
