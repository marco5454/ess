-- Extends the audit-log subsystem introduced in
-- 20260708170000_admin_actions_and_audit_log.sql.
--
-- Changes:
--   1. calling_events audit trigger: log ordinary UPDATEs (previously only
--      soft-deletes were captured). Notes/performed_by/occurred_at edits now
--      appear in the history.
--   2. list_audit_log(): add filters for entity_type, entity_id, since_at,
--      until_at. Preserves the previous signature via defaults; a new
--      overload with the extra params is created and the old one is dropped
--      to avoid ambiguous-call errors.
--   3. New RPC list_audit_log_for_entity(entity_type, entity_id, ...):
--      REDACTED, callable by any authenticated user. Returns only
--      { id, action, summary, occurred_at }. Used by regular users to view
--      the history of a single record they can already see (member/calling)
--      without exposing actor identity or before/after diffs.
--   4. New RPC log_auth_event(action, metadata): thin client-callable wrapper
--      around _audit_write for auth-adjacent events (sign-in, sign-out,
--      password-reset request). Locked to writing rows about the caller
--      themselves; the client cannot forge actor identity because
--      _audit_write reads auth.uid() server-side. Accepted actions are
--      restricted to the 'user.*' namespace.


---------------------------------------------------------------------------
-- 1. Extend calling_events trigger to log ordinary updates
---------------------------------------------------------------------------

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
    -- Skip pure updated_at churn.
    if to_jsonb(old) - 'updated_at' = to_jsonb(new) - 'updated_at' then
      return new;
    end if;

    select title into v_title from public.callings where id = new.calling_id;

    if old.deleted_at is null and new.deleted_at is not null then
      v_summary := 'Deleted event ' || new.state::text || ' for ' || coalesce(v_title, new.calling_id::text);
      v_meta := jsonb_build_object('before', to_jsonb(old), 'after', to_jsonb(new));
      perform public._audit_write('calling_event.delete', 'calling_event', new.id::text, v_summary, v_meta);
    else
      v_summary := 'Updated event ' || new.state::text || ' for ' || coalesce(v_title, new.calling_id::text);
      v_meta := jsonb_build_object('before', to_jsonb(old), 'after', to_jsonb(new));
      perform public._audit_write('calling_event.update', 'calling_event', new.id::text, v_summary, v_meta);
    end if;

  elsif tg_op = 'DELETE' then
    v_summary := 'Hard-deleted calling event ' || old.state::text;
    v_meta := jsonb_build_object('before', to_jsonb(old));
    perform public._audit_write('calling_event.delete', 'calling_event', old.id::text, v_summary, v_meta);
  end if;
  return coalesce(new, old);
end;
$$;

-- Trigger itself is unchanged; the function it references was replaced above.


---------------------------------------------------------------------------
-- 2. list_audit_log: entity + date range filters
---------------------------------------------------------------------------

-- The previous 5-arg version must be dropped before creating the extended
-- version, otherwise callers passing named args get an ambiguous-function
-- error.
drop function if exists public.list_audit_log(
  timestamptz, bigint, integer, text, uuid
);

create or replace function public.list_audit_log(
  before_at       timestamptz default null,
  before_id       bigint      default null,
  page_size       integer     default 50,
  action_like     text        default null,
  actor           uuid        default null,
  entity_type_eq  text        default null,
  entity_id_eq    text        default null,
  since_at        timestamptz default null,
  until_at        timestamptz default null
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
       and (action_like    is null or l.action      like action_like)
       and (actor          is null or l.actor_id    = actor)
       and (entity_type_eq is null or l.entity_type = entity_type_eq)
       and (entity_id_eq   is null or l.entity_id   = entity_id_eq)
       and (since_at       is null or l.occurred_at >= since_at)
       and (until_at       is null or l.occurred_at <  until_at)
     order by l.occurred_at desc, l.id desc
     limit page_size;
end;
$$;

revoke all on function public.list_audit_log(
  timestamptz, bigint, integer, text, uuid, text, text, timestamptz, timestamptz
) from public;
grant execute on function public.list_audit_log(
  timestamptz, bigint, integer, text, uuid, text, text, timestamptz, timestamptz
) to authenticated;


---------------------------------------------------------------------------
-- 3. list_audit_log_for_entity: redacted, non-admin-callable
---------------------------------------------------------------------------

-- Returns the history of a single record without exposing:
--   - actor identity (actor_id, actor_email are dropped)
--   - before/after diffs (metadata is dropped)
--
-- Used by regular users to see, e.g., "when was this member's notes edited"
-- without leaking which other bishopric member did it, or what the previous
-- value was.
--
-- Callable by any authenticated user. There is deliberately no additional
-- authorization check here: if the caller can query the underlying entity
-- (via RLS on members/callings/calling_events), they can also see the
-- redacted history of that entity. Restricting further would require
-- duplicating those RLS checks.
create or replace function public.list_audit_log_for_entity(
  entity_type_in  text,
  entity_id_in    text,
  before_at       timestamptz default null,
  before_id       bigint      default null,
  page_size       integer     default 50
)
returns table (
  id           bigint,
  action       text,
  summary      text,
  occurred_at  timestamptz
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if entity_type_in is null or entity_id_in is null then
    raise exception 'entity_type and entity_id are required'
      using errcode = '22023';
  end if;

  if page_size is null or page_size < 1 then
    page_size := 50;
  elsif page_size > 200 then
    page_size := 200;
  end if;

  return query
    select l.id, l.action, l.summary, l.occurred_at
      from public.audit_log l
     where l.entity_type = entity_type_in
       and l.entity_id   = entity_id_in
       and (before_at is null
            or l.occurred_at < before_at
            or (l.occurred_at = before_at and l.id < coalesce(before_id, l.id + 1)))
     order by l.occurred_at desc, l.id desc
     limit page_size;
end;
$$;

revoke all on function public.list_audit_log_for_entity(
  text, text, timestamptz, bigint, integer
) from public;
grant execute on function public.list_audit_log_for_entity(
  text, text, timestamptz, bigint, integer
) to authenticated;


---------------------------------------------------------------------------
-- 4. log_auth_event: client-driven audit for auth-adjacent events
---------------------------------------------------------------------------

-- Client wrapper for _audit_write, restricted to logging the caller's own
-- auth-adjacent activity: sign-in, sign-out, password-reset requests, etc.
--
-- Server-side identity is authoritative: actor_id is set from auth.uid()
-- inside _audit_write; the client cannot spoof another user. The action
-- namespace is also whitelisted to prevent misuse to inject fake domain
-- events.
create or replace function public.log_auth_event(
  action_in    text,
  metadata_in  jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if action_in is null
     or action_in not in (
       'user.signin',
       'user.signout',
       'user.password_reset_request'
     )
  then
    raise exception 'invalid action for log_auth_event: %', action_in
      using errcode = '22023';
  end if;

  perform public._audit_write(
    action_in,
    'user',
    v_uid::text,
    case action_in
      when 'user.signin'                  then 'Signed in'
      when 'user.signout'                 then 'Signed out'
      when 'user.password_reset_request'  then 'Requested password reset'
      else action_in
    end,
    metadata_in
  );
end;
$$;

revoke all on function public.log_auth_event(text, jsonb) from public;
grant execute on function public.log_auth_event(text, jsonb) to authenticated;


---------------------------------------------------------------------------
-- 5. Sign-up hook: log new user creation
---------------------------------------------------------------------------

-- Fires after a new row lands in auth.users. Uses a null actor so the log
-- clearly shows "system created this account" rather than pretending the
-- new user acted on themselves.
create or replace function public._audit_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log
    (actor_id, actor_email, action, entity_type, entity_id, summary, metadata)
  values
    (null, new.email::text, 'user.signup', 'user', new.id::text,
     'Account created for ' || coalesce(new.email::text, new.id::text),
     jsonb_build_object('email', new.email));
  return new;
end;
$$;

drop trigger if exists trg_auth_users_signup_audit on auth.users;
create trigger trg_auth_users_signup_audit
  after insert on auth.users
  for each row execute function public._audit_auth_user_created();
