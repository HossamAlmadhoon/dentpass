-- DentPass v5: negotiable prices with offers, paying the host by InstaPay, marking a booking as paid.

-- ---------------------------------------------------------------------------
-- New columns
-- ---------------------------------------------------------------------------
-- The host can let people suggest their own price
alter table public.slots add column if not exists negotiable boolean not null default false;

-- What the person suggested (when the price is negotiable), and when they said they paid
alter table public.bookings add column if not exists offer_egp int check (offer_egp is null or offer_egp between 0 and 1000000);
alter table public.bookings add column if not exists paid_at timestamptz;

-- Where the host receives payments: an InstaPay address or mobile number
alter table public.profiles add column if not exists instapay text check (instapay is null or char_length(instapay) <= 60);

-- ---------------------------------------------------------------------------
-- Feed and slot page: say whether the price is negotiable
-- ---------------------------------------------------------------------------
drop function if exists public.get_feed(public.slot_kind[], text, text, timestamptz, timestamptz, uuid);
create function public.get_feed(
  p_kind public.slot_kind[] default null,
  p_area text default null,
  p_query text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_host uuid default null
)
returns table (
  id uuid, host_id uuid, host_name text, kind public.slot_kind, title text, description text,
  area text, address text, starts_at timestamptz, ends_at timestamptz, capacity int, taken int,
  price_egp int, need_role public.member_role, photo_path text, is_open boolean,
  photo_paths text[], lat double precision, lng double precision, host_rating numeric, host_reviews int,
  negotiable boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_approved() then raise exception 'not approved'; end if;
  return query
    select s.id, s.host_id, p.full_name, s.kind, s.title, s.description, s.area, ''::text,
           s.starts_at, s.ends_at, s.capacity, public.slot_taken(s.id), s.price_egp, s.need_role,
           s.photo_path, s.is_open, s.photo_paths,
           round(s.lat::numeric, 2)::double precision, round(s.lng::numeric, 2)::double precision,
           r.rating, r.reviews, s.negotiable
    from public.slots s
    join public.profiles p on p.id = s.host_id
    cross join lateral public.member_rating(s.host_id) r
    where s.is_open
      and s.starts_at > now()
      and p.status = 'approved'
      and (p_kind is null or s.kind = any (p_kind))
      and (p_area is null or s.area = p_area)
      and (p_host is null or s.host_id = p_host)
      and (p_from is null or s.starts_at >= p_from)
      and (p_to is null or s.starts_at < p_to)
      and (p_query is null or p_query = ''
           or s.title ilike '%' || p_query || '%'
           or s.description ilike '%' || p_query || '%'
           or p.full_name ilike '%' || p_query || '%')
    order by s.starts_at
    limit 200;
end;
$$;

drop function if exists public.get_slot(uuid);
create function public.get_slot(p_slot uuid)
returns table (
  id uuid, host_id uuid, host_name text, kind public.slot_kind, title text, description text,
  area text, address text, starts_at timestamptz, ends_at timestamptz, capacity int, taken int,
  price_egp int, need_role public.member_role, photo_path text, is_open boolean, host_phone text,
  photo_paths text[], lat double precision, lng double precision, host_rating numeric, host_reviews int,
  exact_location boolean, negotiable boolean, host_instapay text, host_avatar text
)
language plpgsql stable security definer set search_path = public as $$
declare
  insider boolean;
begin
  if not (public.is_approved() or public.is_admin()
          or exists (select 1 from public.slots where slots.id = p_slot and slots.host_id = auth.uid())) then
    raise exception 'not approved';
  end if;
  -- The host, and people the host accepted, see the exact address, location, phone and InstaPay
  select exists (select 1 from public.slots x where x.id = p_slot and x.host_id = auth.uid())
      or exists (select 1 from public.bookings b where b.slot_id = p_slot and b.user_id = auth.uid() and b.status = 'accepted')
    into insider;
  return query
    select s.id, s.host_id, p.full_name, s.kind, s.title, s.description, s.area,
           case when insider then s.address else '' end,
           s.starts_at, s.ends_at, s.capacity, public.slot_taken(s.id), s.price_egp, s.need_role,
           s.photo_path, s.is_open,
           case when insider and s.host_id <> auth.uid() then p.phone else null end,
           s.photo_paths,
           case when insider then s.lat else round(s.lat::numeric, 2)::double precision end,
           case when insider then s.lng else round(s.lng::numeric, 2)::double precision end,
           r.rating, r.reviews, insider, s.negotiable,
           case when insider and s.host_id <> auth.uid() then p.instapay else null end,
           p.avatar_path
    from public.slots s
    join public.profiles p on p.id = s.host_id
    cross join lateral public.member_rating(s.host_id) r
    where s.id = p_slot;
end;
$$;

-- ---------------------------------------------------------------------------
-- Booking with an optional price offer
-- ---------------------------------------------------------------------------
drop function if exists public.book_slot(uuid, text);
create function public.book_slot(p_slot uuid, p_message text default '', p_offer int default null)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  s public.slots;
  me public.profiles;
  fee numeric;
  price int;
  offer int;
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

  -- An offer only counts when the host allowed it
  if p_offer is not null and p_offer >= 0 and s.negotiable then
    offer := least(p_offer, 1000000);
  end if;
  price := coalesce(offer, s.price_egp);

  select fee_percent into fee from public.app_settings;

  insert into public.bookings (slot_id, user_id, message, price_egp, fee_egp, offer_egp)
  values (s.id, me.id, left(coalesce(p_message, ''), 500), price,
          case when s.kind = 'cover' then 0 else round(price * fee / 100) end, offer)
  on conflict (slot_id, user_id) do update
    set status = 'pending', message = excluded.message, price_egp = excluded.price_egp,
        fee_egp = excluded.fee_egp, offer_egp = excluded.offer_egp, paid_at = null, updated_at = now()
    where public.bookings.status in ('cancelled', 'declined')
  returning * into result;

  if result.id is null then raise exception 'already booked'; end if;

  perform public.notify(s.host_id, 'booking_requested', s.id, result.id);
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- "I've paid": the person who booked tells the host they sent the money
-- ---------------------------------------------------------------------------
create or replace function public.mark_paid(p_booking uuid)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  s public.slots;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b.id is null or b.user_id <> auth.uid() then raise exception 'booking not found'; end if;
  if b.status <> 'accepted' then raise exception 'not accepted'; end if;
  if b.paid_at is not null then return b; end if;
  update public.bookings set paid_at = now(), updated_at = now() where id = b.id returning * into b;
  select * into s from public.slots where id = b.slot_id;
  perform public.notify(s.host_id, 'booking_paid', s.id, b.id);
  return b;
end;
$$;

-- ---------------------------------------------------------------------------
-- Host's request list: offers and payments
-- ---------------------------------------------------------------------------
drop function if exists public.get_slot_requests(uuid);
create function public.get_slot_requests(p_slot uuid)
returns table (
  id uuid, user_id uuid, status public.booking_status, message text, created_at timestamptz,
  full_name text, role public.member_role, phone text, price_egp int, fee_egp int,
  rating numeric, reviews int, reviewed boolean, verified boolean, offer_egp int, paid_at timestamptz
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
           p.status = 'approved', b.offer_egp, b.paid_at
    from public.bookings b
    join public.profiles p on p.id = b.user_id
    cross join lateral public.member_rating(b.user_id) r
    where b.slot_id = p_slot
    order by b.created_at;
end;
$$;

revoke execute on function public.get_feed, public.get_slot, public.get_slot_requests, public.book_slot, public.mark_paid
  from public, anon;
grant execute on function public.get_feed, public.get_slot, public.get_slot_requests, public.book_slot, public.mark_paid
  to authenticated;
