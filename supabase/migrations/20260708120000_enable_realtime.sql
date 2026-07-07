-- Enable realtime replication for the app's tables so clients can subscribe
-- via `supabase.from('...').stream(...)`. Adds the tables to the
-- `supabase_realtime` publication that the Supabase realtime service listens on.
--
-- RLS still applies — subscribers only see rows they're allowed to see.

alter publication supabase_realtime add table public.members;
alter publication supabase_realtime add table public.callings;
alter publication supabase_realtime add table public.calling_events;
