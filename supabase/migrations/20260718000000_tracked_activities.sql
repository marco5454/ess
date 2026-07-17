-- Tracked activities
--
-- A generic "task" table for lightweight ward bookkeeping items that do NOT
-- go through the full callings lifecycle (selected → sustained → set apart).
-- Examples: temple recommend interviews, ministering interviews, youth
-- interviews, tithing settlement follow-ups.
--
-- Unlike `callings`, an activity keeps its status inline (mutable column)
-- rather than as an append-only event stream. The status transitions here
-- are simple and reversible, so an audit-log-like history isn't worth the
-- weight.

-- -----------------------------------------------------------------------------
-- Enum: activity_status
-- -----------------------------------------------------------------------------

create type public.activity_status as enum (
  'pending',
  'in_progress',
  'completed',
  'cancelled'
);

-- -----------------------------------------------------------------------------
-- Table: tracked_activities
-- -----------------------------------------------------------------------------
--
-- * `member_id` is nullable so an activity can be ward-wide (a follow-up
--   with no specific candidate) or later be re-scoped without losing the
--   row. `on delete set null` matches: archiving/removing a member should
--   not cascade-delete their historical activities.
-- * `kind` is a freeform text tag ('temple_recommend', 'ministering_interview',
--   'youth_interview', 'tithing_settlement', 'follow_up', 'other'). Kept as
--   text (not an enum) so new categories don't require a migration.
-- * `deleted_at` mirrors the soft-delete tombstone used by the offline sync
--   layer (see `20260708160000_offline_sync_columns.sql`).

create table public.tracked_activities (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid references public.members(id) on delete set null,
  title        text not null,
  kind         text not null,
  status       public.activity_status not null default 'pending',
  due_at       timestamptz,
  completed_at timestamptz,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create index idx_tracked_activities_member on public.tracked_activities (member_id);
create index idx_tracked_activities_status on public.tracked_activities (status);
create index idx_tracked_activities_due_at on public.tracked_activities (due_at);
create index idx_tracked_activities_kind on public.tracked_activities (kind);

create trigger trg_tracked_activities_set_updated_at
  before update on public.tracked_activities
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Row-Level Security
-- -----------------------------------------------------------------------------

alter table public.tracked_activities enable row level security;

create policy "authenticated_all_tracked_activities"
  on public.tracked_activities
  for all
  to authenticated
  using (true)
  with check (true);

-- -----------------------------------------------------------------------------
-- Realtime replication
-- -----------------------------------------------------------------------------

alter publication supabase_realtime add table public.tracked_activities;
