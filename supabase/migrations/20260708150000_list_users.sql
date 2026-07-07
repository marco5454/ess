-- Admin-facing RPC to list registered users.
--
-- Reads from auth.users, which is not exposed to PostgREST directly. This
-- function is SECURITY DEFINER and gated by public.is_admin() so only
-- entries in public.admins can invoke it.

create or replace function public.list_users()
returns table(
  id uuid,
  email text,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  created_at timestamptz,
  is_admin boolean
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

  return query
    select
      u.id,
      u.email::text,
      u.email_confirmed_at,
      u.last_sign_in_at,
      u.created_at,
      (a.user_id is not null) as is_admin
    from auth.users u
    left join public.admins a on a.user_id = u.id
    order by u.created_at desc;
end;
$$;

revoke all on function public.list_users() from public;
grant execute on function public.list_users() to authenticated;
