-- Adds an optional, user-facing free-text "performed by" attribution to
-- calling_events. This is descriptive (e.g. "Bishop Smith", "Elder Jones")
-- and is independent from `recorded_by`, which is the auth.users UUID of
-- the person who tapped Save on their device. `recorded_by` remains for
-- audit/telemetry; `performed_by` is shown in the UI.

alter table public.calling_events
  add column if not exists performed_by text;

comment on column public.calling_events.performed_by is
  'Optional free-text attribution: who actually performed the action (e.g. "Bishop Smith"). Distinct from recorded_by, which is the auth.users id of whoever saved the event.';
