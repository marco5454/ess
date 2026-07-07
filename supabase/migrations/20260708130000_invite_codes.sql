-- Invite-code gate for user self-registration.
--
-- The app's LoginScreen exposes a "Create account" flow that requires an
-- invite code. Admins pre-seed rows in `invite_codes` (via the Supabase
-- dashboard SQL editor) and share the raw code with each bishopric member
-- who should be able to sign up.
--
-- The table's RLS blocks all direct client access; codes are validated and
-- consumed exclusively through the SECURITY DEFINER function
-- `consume_invite_code`, which is granted to `anon` so it can be called
-- immediately after `auth.signUp` (before the user has confirmed their
-- email and signed in).

create table if not exists public.invite_codes (
  code text primary key,
  note text,
  created_at timestamptz not null default now(),
  used_at timestamptz,
  used_by uuid references auth.users on delete set null
);

alter table public.invite_codes enable row level security;

-- No policies for anon / authenticated: direct SELECT/INSERT/UPDATE/DELETE
-- are all denied. Access happens exclusively via consume_invite_code below.

-- Atomically validate an invite code and mark it consumed for the given
-- user. Returns true when the code existed and was unused (and is now
-- marked used); false otherwise. Idempotency: calling with an already-used
-- code returns false without side effects.
--
-- Callable from anon because it runs immediately after auth.signUp, when
-- the newly-created user has not yet confirmed their email.
create or replace function public.consume_invite_code(
  code_input text,
  user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_count integer;
begin
  update public.invite_codes
     set used_at = now(),
         used_by = user_id
   where code = code_input
     and used_at is null;

  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.consume_invite_code(text, uuid) from public;
grant execute on function public.consume_invite_code(text, uuid) to anon;
grant execute on function public.consume_invite_code(text, uuid) to authenticated;

-- Optional convenience: read-only pre-flight check so the client can warn
-- the user before submitting the signUp form. Not authoritative (racy) —
-- consume_invite_code is the ground truth.
create or replace function public.check_invite_code(code_input text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.invite_codes
     where code = code_input
       and used_at is null
  );
$$;

revoke all on function public.check_invite_code(text) from public;
grant execute on function public.check_invite_code(text) to anon;
grant execute on function public.check_invite_code(text) to authenticated;
