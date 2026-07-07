-- Admin-only invite-code management.
--
-- Adds a `public.admins` table holding the user ids of app administrators
-- and four SECURITY DEFINER RPCs the client uses to manage invite codes:
--   - is_admin()                -> boolean          (auth'd caller)
--   - list_invite_codes()       -> setof rows       (admin-only)
--   - create_invite_code(note)  -> the new code     (admin-only)
--   - revoke_invite_code(code)  -> boolean          (admin-only)
--
-- The admins table itself is invisible to clients (RLS blocks all direct
-- access); membership can only be queried via is_admin(). Bootstrap the
-- first admin by inserting a row from the Supabase dashboard SQL editor.

create table if not exists public.admins (
  user_id uuid primary key references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  note text
);

alter table public.admins enable row level security;
-- No policies: all direct client access is denied. Membership queries go
-- through is_admin(); management is out-of-band (dashboard SQL editor).

-- Returns true if the current auth user is in public.admins.
--
-- SECURITY DEFINER so RLS on `public.admins` doesn't hide the row from the
-- check. Callable by authenticated clients only (anon has no session and
-- therefore no user id).
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins where user_id = auth.uid()
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Returns all invite codes, newest first. Admin-only; raises on
-- unauthorized callers.
create or replace function public.list_invite_codes()
returns table (
  code text,
  note text,
  created_at timestamptz,
  used_at timestamptz,
  used_by uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return query
    select ic.code, ic.note, ic.created_at, ic.used_at, ic.used_by
      from public.invite_codes ic
     order by ic.created_at desc;
end;
$$;

revoke all on function public.list_invite_codes() from public;
grant execute on function public.list_invite_codes() to authenticated;

-- Generate and persist a random invite code with an optional note; return
-- the raw code so the caller can copy / share it. Admin-only.
--
-- Retries up to 5 times on the astronomically unlikely event of a code
-- collision (8 uppercase alphanumerics = ~2.8e12 combinations).
create or replace function public.create_invite_code(note_input text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- ambiguity-free
  attempts integer := 0;
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  loop
    -- 8 chars, upper alnum minus 0/O/1/I to avoid transcription errors
    new_code := '';
    for i in 1..8 loop
      new_code := new_code
        || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;

    begin
      insert into public.invite_codes (code, note)
        values (new_code, nullif(trim(coalesce(note_input, '')), ''));
      return new_code;
    exception when unique_violation then
      attempts := attempts + 1;
      if attempts >= 5 then
        raise;
      end if;
    end;
  end loop;
end;
$$;

revoke all on function public.create_invite_code(text) from public;
grant execute on function public.create_invite_code(text) to authenticated;

-- Delete an unused invite code. Returns true if a row was deleted, false
-- otherwise (code missing, or already used). Used codes cannot be revoked
-- via this RPC on purpose: they represent real user memberships and
-- deleting them would blur the audit trail.
create or replace function public.revoke_invite_code(code_input text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted integer;
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  delete from public.invite_codes
   where code = code_input
     and used_at is null;

  get diagnostics deleted = row_count;
  return deleted = 1;
end;
$$;

revoke all on function public.revoke_invite_code(text) from public;
grant execute on function public.revoke_invite_code(text) to authenticated;
