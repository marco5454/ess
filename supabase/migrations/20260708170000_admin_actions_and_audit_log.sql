-- Admin actions (user management) and audit log.
--
-- This migration adds:
--   1. `public.audit_log` table + admin-only RLS + helper writer function.
--   2. Data-table audit triggers on `members`, `callings`, `calling_events`
--      that capture insert/update/delete with the acting user id snapshot.
--   3. Admin user-management RPCs:
--        - grant_admin(target uuid)                 -> boolean
--        - revoke_admin(target uuid)                -> boolean
--        - delete_user(target uuid)                 -> boolean
--        - bootstrap_first_admin(target uuid)       -> boolean
--   4. Audit inserts inside `create_invite_code` and `revoke_invite_code`
--      (rewritten in place, not new functions) so invite-code activity
--      appears in the log too.
--
-- Guardrails baked into the admin RPCs:
--   - revoke_admin/delete_user refuse to leave zero admins (would lock the
--     app out of user management entirely).
--   - revoke_admin/delete_user refuse to act on self when the caller is the
--     only remaining admin. Small footgun guard.
--   - bootstrap_first_admin only succeeds when public.admins is empty. Once
--     any admin exists, all further admin grants must go through grant_admin
--     which requires an existing admin session.
--
-- Audit log is server-side only. It is NOT added to the supabase_realtime
-- publication and it is NOT mirrored to the client's Drift database. Admins
-- read it on-demand while online via `list_audit_log()`.


---------------------------------------------------------------------------
-- 1. Audit log table
---------------------------------------------------------------------------

create table if not exists public.audit_log (
  id           bigserial primary key,
  actor_id     uuid references auth.users on delete set null,
  actor_email  text,                       -- snapshot; survives user deletion
  action       text not null,              -- e.g. 'member.update', 'admin.grant'
  entity_type  text,                       -- 'member' | 'calling' | 'calling_event'
                                           -- | 'admin' | 'invite_code' | 'user'
  entity_id    text,                       -- uuid or code, text for polymorphism
  summary      text,                       -- human-readable one-liner
  metadata     jsonb,                      -- structured detail (before/after diff, etc.)
  occurred_at  timestamptz not null default now()
);

create index if not exists idx_audit_log_occurred_at
  on public.audit_log (occurred_at desc);
create index if not exists idx_audit_log_actor_id
  on public.audit_log (actor_id);
create index if not exists idx_audit_log_action
  on public.audit_log (action);
create index if not exists idx_audit_log_entity
  on public.audit_log (entity_type, entity_id);

alter table public.audit_log enable row level security;
-- No policies. All reads go through list_audit_log() (admin-gated). All
-- writes come from triggers or SECURITY DEFINER functions running as the
-- table owner, which bypasses RLS.


---------------------------------------------------------------------------
-- 2. Internal audit writer
---------------------------------------------------------------------------

-- Writes an audit_log row using the current auth context. Called from
-- both triggers and other SECURITY DEFINER functions.
--
-- Marked SECURITY DEFINER so it can insert into audit_log even when the
-- calling context is a trigger fired by a client that has no direct
-- insert privilege on the table (RLS denies all direct writes).
create or replace function public._audit_write(
  p_action       text,
  p_entity_type  text,
  p_entity_id    text,
  p_summary      text,
  p_metadata     jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id    uuid;
  v_actor_email text;
begin
  v_actor_id := auth.uid();
  -- Snapshot the email so a later user deletion doesn't orphan the trail.
  select email::text into v_actor_email
    from auth.users where id = v_actor_id;

  insert into public.audit_log
    (actor_id, actor_email, action, entity_type, entity_id, summary, metadata)
  values
    (v_actor_id, v_actor_email, p_action, p_entity_type, p_entity_id, p_summary, p_metadata);
end;
$$;

revoke all on function public._audit_write(text, text, text, text, jsonb) from public;
-- Not granted to any role: only reachable from SECURITY DEFINER functions
-- and triggers running as the owner. Direct RPC access is denied.


---------------------------------------------------------------------------
-- 3. Data-table audit triggers
---------------------------------------------------------------------------

-- Members
create or replace function public._audit_members_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_summary text;
  v_meta    jsonb;
begin
  if tg_op = 'INSERT' then
    v_summary := 'Created member ' || coalesce(new.first_name, '') || ' ' || coalesce(new.last_name, '');
    v_meta := jsonb_build_object('after', to_jsonb(new));
    perform public._audit_write('member.create', 'member', new.id::text, v_summary, v_meta);
  elsif tg_op = 'UPDATE' then
    -- Skip pure updated_at churn (no meaningful column changed).
    if to_jsonb(old) - 'updated_at' = to_jsonb(new) - 'updated_at' then
      return new;
    end if;
    v_summary := 'Updated member ' || coalesce(new.first_name, '') || ' ' || coalesce(new.last_name, '');
    v_meta := jsonb_build_object(
      'before', to_jsonb(old),
      'after',  to_jsonb(new)
    );
    perform public._audit_write('member.update', 'member', new.id::text, v_summary, v_meta);
  elsif tg_op = 'DELETE' then
    v_summary := 'Deleted member ' || coalesce(old.first_name, '') || ' ' || coalesce(old.last_name, '');
    v_meta := jsonb_build_object('before', to_jsonb(old));
    perform public._audit_write('member.delete', 'member', old.id::text, v_summary, v_meta);
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_members_audit on public.members;
create trigger trg_members_audit
  after insert or update or delete on public.members
  for each row execute function public._audit_members_change();


-- Callings
create or replace function public._audit_callings_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_summary text;
  v_meta    jsonb;
  v_member  text;
begin
  if tg_op = 'INSERT' then
    select first_name || ' ' || last_name into v_member
      from public.members where id = new.member_id;
    v_summary := 'Created calling ' || new.title || ' for ' || coalesce(v_member, new.member_id::text);
    v_meta := jsonb_build_object('after', to_jsonb(new));
    perform public._audit_write('calling.create', 'calling', new.id::text, v_summary, v_meta);
  elsif tg_op = 'UPDATE' then
    if to_jsonb(old) - 'updated_at' = to_jsonb(new) - 'updated_at' then
      return new;
    end if;
    -- Distinguish soft-delete from a normal update.
    if old.deleted_at is null and new.deleted_at is not null then
      v_summary := 'Deleted calling ' || new.title;
      v_meta := jsonb_build_object('before', to_jsonb(old), 'after', to_jsonb(new));
      perform public._audit_write('calling.delete', 'calling', new.id::text, v_summary, v_meta);
    else
      v_summary := 'Updated calling ' || new.title;
      v_meta := jsonb_build_object('before', to_jsonb(old), 'after', to_jsonb(new));
      perform public._audit_write('calling.update', 'calling', new.id::text, v_summary, v_meta);
    end if;
  elsif tg_op = 'DELETE' then
    v_summary := 'Hard-deleted calling ' || old.title;
    v_meta := jsonb_build_object('before', to_jsonb(old));
    perform public._audit_write('calling.delete', 'calling', old.id::text, v_summary, v_meta);
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_callings_audit on public.callings;
create trigger trg_callings_audit
  after insert or update or delete on public.callings
  for each row execute function public._audit_callings_change();


-- Calling events (append-only lifecycle log)
create or replace function public._audit_calling_events_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_summary text;
  v_meta    jsonb;
  v_title   text;
begin
  if tg_op = 'INSERT' then
    select title into v_title from public.callings where id = new.calling_id;
    v_summary := 'Recorded ' || new.state::text || ' for ' || coalesce(v_title, new.calling_id::text);
    v_meta := jsonb_build_object('after', to_jsonb(new));
    perform public._audit_write('calling_event.create', 'calling_event', new.id::text, v_summary, v_meta);
  elsif tg_op = 'UPDATE' then
    if to_jsonb(old) - 'updated_at' = to_jsonb(new) - 'updated_at' then
      return new;
    end if;
    -- Soft-delete transition on an event is the only meaningful mutation.
    if old.deleted_at is null and new.deleted_at is not null then
      select title into v_title from public.callings where id = new.calling_id;
      v_summary := 'Deleted event ' || new.state::text || ' for ' || coalesce(v_title, new.calling_id::text);
      v_meta := jsonb_build_object('before', to_jsonb(old), 'after', to_jsonb(new));
      perform public._audit_write('calling_event.delete', 'calling_event', new.id::text, v_summary, v_meta);
    end if;
  elsif tg_op = 'DELETE' then
    v_summary := 'Hard-deleted calling event ' || old.state::text;
    v_meta := jsonb_build_object('before', to_jsonb(old));
    perform public._audit_write('calling_event.delete', 'calling_event', old.id::text, v_summary, v_meta);
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_calling_events_audit on public.calling_events;
create trigger trg_calling_events_audit
  after insert or update or delete on public.calling_events
  for each row execute function public._audit_calling_events_change();


---------------------------------------------------------------------------
-- 4. Admin user-management RPCs
---------------------------------------------------------------------------

-- Count admins. Used by the guardrails below.
create or replace function public._admin_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from public.admins;
$$;

revoke all on function public._admin_count() from public;


-- Promote a user to admin. Admin-only. Idempotent: succeeds silently if the
-- target is already an admin.
create or replace function public.grant_admin(target_user uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text;
  v_exists boolean;
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select email::text into v_email from auth.users where id = target_user;
  if v_email is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  insert into public.admins (user_id)
    values (target_user)
    on conflict (user_id) do nothing;

  get diagnostics v_exists = row_count;

  if v_exists then
    perform public._audit_write(
      'admin.grant',
      'user',
      target_user::text,
      'Granted admin to ' || v_email,
      jsonb_build_object('target_email', v_email)
    );
  end if;

  return true;
end;
$$;

revoke all on function public.grant_admin(uuid) from public;
grant execute on function public.grant_admin(uuid) to authenticated;


-- Demote a user from admin. Refuses to leave zero admins.
create or replace function public.revoke_admin(target_user uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email    text;
  v_deleted  integer;
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- If the target is the only admin, refuse. We check membership first so
  -- the message is accurate whether the caller is the target or not.
  if exists (select 1 from public.admins where user_id = target_user)
     and public._admin_count() <= 1 then
    raise exception 'cannot revoke the last remaining admin'
      using errcode = 'P0001';
  end if;

  select email::text into v_email from auth.users where id = target_user;

  delete from public.admins where user_id = target_user;
  get diagnostics v_deleted = row_count;

  if v_deleted > 0 then
    perform public._audit_write(
      'admin.revoke',
      'user',
      target_user::text,
      'Revoked admin from ' || coalesce(v_email, target_user::text),
      jsonb_build_object('target_email', v_email)
    );
  end if;

  return v_deleted > 0;
end;
$$;

revoke all on function public.revoke_admin(uuid) from public;
grant execute on function public.revoke_admin(uuid) to authenticated;


-- Delete a user entirely. Admin-only. Guardrails:
--   - Cannot delete self.
--   - Cannot delete the last remaining admin.
--
-- Cascades handled by existing FKs:
--   - public.admins.user_id           ON DELETE CASCADE
--   - public.invite_codes.used_by     ON DELETE SET NULL
--   - public.calling_events.recorded_by ON DELETE SET NULL
--
-- Members / callings owned by the ward are unaffected; users are just
-- session identities, not domain data.
create or replace function public.delete_user(target_user uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text;
  v_deleted integer;
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if target_user = auth.uid() then
    raise exception 'cannot delete your own account'
      using errcode = 'P0001';
  end if;

  if exists (select 1 from public.admins where user_id = target_user)
     and public._admin_count() <= 1 then
    raise exception 'cannot delete the last remaining admin'
      using errcode = 'P0001';
  end if;

  select email::text into v_email from auth.users where id = target_user;
  if v_email is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  delete from auth.users where id = target_user;
  get diagnostics v_deleted = row_count;

  if v_deleted > 0 then
    perform public._audit_write(
      'user.delete',
      'user',
      target_user::text,
      'Deleted user ' || v_email,
      jsonb_build_object('target_email', v_email)
    );
  end if;

  return v_deleted > 0;
end;
$$;

revoke all on function public.delete_user(uuid) from public;
grant execute on function public.delete_user(uuid) to authenticated;


-- Bootstrap the very first admin. Callable by any authenticated user, but
-- only succeeds while public.admins is empty. Once the first admin exists,
-- all further promotions go through grant_admin() which requires an
-- existing admin session.
--
-- This exists so a fresh install can promote its first user without going
-- through the Supabase SQL editor.
create or replace function public.bootstrap_first_admin(target_user uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if public._admin_count() > 0 then
    raise exception 'admins already exist; use grant_admin instead'
      using errcode = 'P0001';
  end if;

  select email::text into v_email from auth.users where id = target_user;
  if v_email is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;

  insert into public.admins (user_id, note)
    values (target_user, 'bootstrap');

  perform public._audit_write(
    'admin.bootstrap',
    'user',
    target_user::text,
    'Bootstrapped first admin ' || v_email,
    jsonb_build_object('target_email', v_email)
  );

  return true;
end;
$$;

revoke all on function public.bootstrap_first_admin(uuid) from public;
grant execute on function public.bootstrap_first_admin(uuid) to authenticated;


---------------------------------------------------------------------------
-- 5. Invite-code RPC audit hooks
---------------------------------------------------------------------------

-- Rewrite create_invite_code to log to the audit trail.
create or replace function public.create_invite_code(note_input text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  attempts integer := 0;
  clean_note text;
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  clean_note := nullif(trim(coalesce(note_input, '')), '');

  loop
    new_code := '';
    for i in 1..8 loop
      new_code := new_code
        || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;

    begin
      insert into public.invite_codes (code, note)
        values (new_code, clean_note);

      perform public._audit_write(
        'invite.create',
        'invite_code',
        new_code,
        'Generated invite code ' || new_code
          || case when clean_note is not null then ' (' || clean_note || ')' else '' end,
        jsonb_build_object('note', clean_note)
      );

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


-- Rewrite revoke_invite_code to log to the audit trail.
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

  if deleted = 1 then
    perform public._audit_write(
      'invite.revoke',
      'invite_code',
      code_input,
      'Revoked invite code ' || code_input,
      null
    );
  end if;

  return deleted = 1;
end;
$$;


---------------------------------------------------------------------------
-- 6. Audit-log read RPC (admin-only)
---------------------------------------------------------------------------

-- Returns audit_log rows filtered by optional predicates. Paginated.
-- Callers pass a `before` timestamp to fetch older pages (keyset pagination
-- on occurred_at, ties broken by id).
create or replace function public.list_audit_log(
  before_at   timestamptz default null,
  before_id   bigint      default null,
  page_size   integer     default 50,
  action_like text        default null,
  actor       uuid        default null
)
returns table (
  id           bigint,
  actor_id     uuid,
  actor_email  text,
  action       text,
  entity_type  text,
  entity_id    text,
  summary      text,
  metadata     jsonb,
  occurred_at  timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  if page_size is null or page_size < 1 then
    page_size := 50;
  elsif page_size > 500 then
    page_size := 500;
  end if;

  return query
    select l.id, l.actor_id, l.actor_email, l.action, l.entity_type,
           l.entity_id, l.summary, l.metadata, l.occurred_at
      from public.audit_log l
     where (before_at is null
            or l.occurred_at < before_at
            or (l.occurred_at = before_at and l.id < coalesce(before_id, l.id + 1)))
       and (action_like is null or l.action like action_like)
       and (actor is null or l.actor_id = actor)
     order by l.occurred_at desc, l.id desc
     limit page_size;
end;
$$;

revoke all on function public.list_audit_log(timestamptz, bigint, integer, text, uuid) from public;
grant execute on function public.list_audit_log(timestamptz, bigint, integer, text, uuid) to authenticated;
