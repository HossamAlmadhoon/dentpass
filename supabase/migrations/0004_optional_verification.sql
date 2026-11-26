-- DentPass: verification becomes optional.
-- Anyone with basic details (name and mobile) can browse, book, rate, report and set alerts.
-- Only members whose syndicate card and ID were approved ("verified") can post slots.

-- ---------------------------------------------------------------------------
-- Who is who
-- ---------------------------------------------------------------------------
-- Verified: papers checked and approved by an admin. Needed to post.
create or replace function public.is_verified()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'approved' from public.profiles where id = auth.uid()), false);
$$;

-- A member who may use the app: basic details filled in and not suspended.
-- (Older rules call this is_approved; it now means "may use the app".)
create or replace function public.is_approved()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select status::text <> 'suspended' and char_length(full_name) > 0 and coalesce(char_length(phone), 0) > 0
    from public.profiles where id = auth.uid()
  ), false);
$$;

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_approved();
$$;

-- Remember the status before a suspension, so reinstating puts it back
alter table public.profiles add column if not exists status_before_suspension text;

-- ---------------------------------------------------------------------------
-- Posting needs verification
-- ---------------------------------------------------------------------------
drop policy if exists "approved members post slots" on public.slots;
drop policy if exists "verified members post slots" on public.slots;
create policy "verified members post slots" on public.slots
  for insert to authenticated
  with check (host_id = auth.uid() and public.is_verified() and starts_at > now());

-- ---------------------------------------------------------------------------
-- Booking: any member (verified or not); hosts see who is verified
-- ---------------------------------------------------------------------------
create or replace function public.book_slot(p_slot uuid, p_message text default '')
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  s public.slots;
  me public.profiles;
  fee numeric;
  result public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or not public.is_member() then raise exception 'not approved'; end if;

  select * into s from public.slots where id = p_slot for update;
  if s.id is null then raise exception 'slot not found'; end if;
  if s.host_id = me.id then raise exception 'cannot book own slot'; end if;
  if not s.is_open or s.starts_at <= now() then raise exception 'slot closed'; end if;
  if s.kind = 'cover' and s.need_role <> me.role then raise exception 'role mismatch'; end if;
  if exists (select 1 from public.bookings b where b.slot_id = s.id and b.user_id = me.id
             and b.status in ('pending', 'accepted')) then
    raise exception 'already booked';
  end if;
  if s.kind <> 'cover' and public.slot_taken(s.id) >= s.capacity then raise exception 'slot full'; end if;

  select fee_percent into fee from public.app_settings;

  insert into public.bookings (slot_id, user_id, message, price_egp, fee_egp)
  values (s.id, me.id, left(coalesce(p_message, ''), 500), s.price_egp,
          case when s.kind = 'cover' then 0 else round(s.price_egp * fee / 100) end)
  on conflict (slot_id, user_id) do update
    set status = 'pending', message = excluded.message, price_egp = excluded.price_egp,
        fee_egp = excluded.fee_egp, updated_at = now()
    where public.bookings.status in ('cancelled', 'declined')
  returning * into result;

  if result.id is null then raise exception 'already booked'; end if;

  perform public.notify(s.host_id, 'booking_requested', s.id, result.id);
  return result;
end;
$$;

drop function if exists public.get_slot_requests(uuid);
create function public.get_slot_requests(p_slot uuid)
returns table (
  id uuid, user_id uuid, status public.booking_status, message text, created_at timestamptz,
  full_name text, role public.member_role, phone text, price_egp int, fee_egp int,
  rating numeric, reviews int, reviewed boolean, verified boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from public.slots s where s.id = p_slot and s.host_id = auth.uid()) then
    raise exception 'not your slot';
  end if;
  return query
    select b.id, b.user_id, b.status, b.message, b.created_at, p.full_name, p.role,
           case when b.status = 'accepted' then p.phone else null end, b.price_egp, b.fee_egp,
           r.rating, r.reviews,
           exists (select 1 from public.reviews v where v.booking_id = b.id and v.reviewer_id = auth.uid()),
           p.status = 'approved'
    from public.bookings b
    join public.profiles p on p.id = b.user_id
    cross join lateral public.member_rating(b.user_id) r
    where b.slot_id = p_slot
    order by b.created_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Member pages for everyone with basic details, with a verified flag
-- ---------------------------------------------------------------------------
drop function if exists public.get_member(uuid);
create function public.get_member(p_user uuid)
returns table (
  id uuid, full_name text, role public.member_role, area text, bio text, avatar_path text,
  member_since timestamptz, rating numeric, reviews int, hosted int, attended int, verified boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_member() or p_user = auth.uid() or public.is_admin()) then raise exception 'not approved'; end if;
  return query
    select p.id, p.full_name, p.role, p.area, p.bio, p.avatar_path, p.created_at,
           r.rating, r.reviews,
           (select count(*)::int from public.slots s where s.host_id = p.id),
           (select count(*)::int from public.bookings b join public.slots s on s.id = b.slot_id
             where b.user_id = p.id and b.status = 'accepted' and s.ends_at < now()),
           p.status = 'approved'
    from public.profiles p, public.member_rating(p.id) r
    where p.id = p_user
      and (p.id = auth.uid() or public.is_admin()
           or (p.status::text <> 'suspended' and char_length(p.full_name) > 0));
end;
$$;

-- ---------------------------------------------------------------------------
-- Alerts reach every member, not only verified ones
-- ---------------------------------------------------------------------------
create or replace function public.slots_alert_matches()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, type, slot_id)
  select distinct a.user_id, 'new_slot', new.id
  from public.slot_alerts a
  join public.profiles p on p.id = a.user_id and p.status::text <> 'suspended'
  where a.user_id <> new.host_id
    and (a.kinds is null or new.kind = any (a.kinds))
    and (a.area is null or a.area = new.area);
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admins can suspend any member; reinstating puts back their earlier status
-- ---------------------------------------------------------------------------
create or replace function public.set_member_status(p_user uuid, p_suspend boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  if p_user = auth.uid() then raise exception 'not yourself'; end if;
  if p_suspend then
    update public.profiles
       set status_before_suspension = status::text, status = 'suspended', rejection_reason = left(p_reason, 300)
     where id = p_user and status::text <> 'suspended';
  else
    update public.profiles
       set status = coalesce(status_before_suspension, 'unverified')::public.verification_status,
           status_before_suspension = null, rejection_reason = null
     where id = p_user and status::text = 'suspended';
  end if;
  if not found then raise exception 'nothing to change'; end if;
  perform public.notify(p_user, case when p_suspend then 'account_suspended' else 'account_reinstated' end, null, null);
end;
$$;

create or replace function public.admin_overview()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  return json_build_object(
    'members', (select count(*) from public.profiles where status = 'approved'),
    'unverified', (select count(*) from public.profiles
                    where status::text in ('unverified', 'rejected') and char_length(full_name) > 0),
    'waiting', (select count(*) from public.profiles where status = 'pending'),
    'suspended', (select count(*) from public.profiles where status::text = 'suspended'),
    'open_slots', (select count(*) from public.slots where is_open and starts_at > now()),
    'bookings_30d', (select count(*) from public.bookings where created_at > now() - interval '30 days'),
    'accepted_30d', (select count(*) from public.bookings where status = 'accepted' and updated_at > now() - interval '30 days'),
    'fees_30d', (select coalesce(sum(fee_egp), 0) from public.bookings where status = 'accepted' and updated_at > now() - interval '30 days')
  );
end;
$$;

revoke execute on function public.get_slot_requests, public.get_member from public, anon;
grant execute on function public.get_slot_requests, public.get_member to authenticated;
