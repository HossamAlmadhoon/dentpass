-- DentPass version 2 database update.
-- Safe to run on the live project: version 1 of the app keeps working with it.
-- Run once in the Supabase SQL Editor (paste all, then Run).

-- ---------------------------------------------------------------------------
-- Members: suspension, public bio and photo
-- ---------------------------------------------------------------------------
alter type public.verification_status add value if not exists 'suspended';

alter table public.profiles
  add column if not exists bio text not null default '' check (char_length(bio) <= 500),
  add column if not exists avatar_path text;

-- ---------------------------------------------------------------------------
-- Slots: several photos and a map location
-- ---------------------------------------------------------------------------
alter table public.slots
  add column if not exists photo_paths text[] not null default '{}' check (cardinality(photo_paths) <= 6),
  add column if not exists lat double precision check (lat between -90 and 90),
  add column if not exists lng double precision check (lng between -180 and 180),
  add column if not exists updated_at timestamptz not null default now();

update public.slots set photo_paths = array[photo_path] where photo_path is not null and photo_paths = '{}';

-- Editing rules: the type can't change, and seats can't drop below people already accepted
create or replace function public.slots_before_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  accepted int;
begin
  if new.kind <> old.kind then raise exception 'cannot change type'; end if;
  if new.host_id <> old.host_id then raise exception 'cannot change host'; end if;
  if new.capacity < old.capacity then
    select count(*) into accepted from public.bookings where slot_id = new.id and status = 'accepted';
    if new.capacity < accepted then raise exception 'capacity below accepted'; end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists slots_before_update on public.slots;
create trigger slots_before_update before update on public.slots
  for each row execute function public.slots_before_update();

-- ---------------------------------------------------------------------------
-- Notifications keep the slot title, so they survive a deleted slot
-- ---------------------------------------------------------------------------
alter table public.notifications add column if not exists slot_title text not null default '';

alter table public.notifications drop constraint if exists notifications_slot_id_fkey;
alter table public.notifications add constraint notifications_slot_id_fkey
  foreign key (slot_id) references public.slots (id) on delete set null;
alter table public.notifications drop constraint if exists notifications_booking_id_fkey;
alter table public.notifications add constraint notifications_booking_id_fkey
  foreign key (booking_id) references public.bookings (id) on delete set null;

create or replace function public.notifications_fill_title()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.slot_id is not null and new.slot_title = '' then
    select title into new.slot_title from public.slots where id = new.slot_id;
    new.slot_title := coalesce(new.slot_title, '');
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_fill_title on public.notifications;
create trigger notifications_fill_title before insert on public.notifications
  for each row execute function public.notifications_fill_title();

update public.notifications n set slot_title = s.title from public.slots s where s.id = n.slot_id and n.slot_title = '';

-- Tell people with a request when the host changes the time, place or price
create or replace function public.slots_after_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.starts_at, new.ends_at, new.address, new.area, new.price_egp)
     is distinct from (old.starts_at, old.ends_at, old.address, old.area, old.price_egp) then
    insert into public.notifications (user_id, type, slot_id)
    select b.user_id, 'slot_updated', new.id from public.bookings b
    where b.slot_id = new.id and b.status in ('pending', 'accepted');
  end if;
  return null;
end;
$$;

drop trigger if exists slots_after_update on public.slots;
create trigger slots_after_update after update on public.slots
  for each row execute function public.slots_after_update();

-- Tell them when the host deletes the slot
create or replace function public.slots_before_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, type, slot_id, slot_title)
  select b.user_id, 'slot_cancelled', null, old.title from public.bookings b
  where b.slot_id = old.id and b.status in ('pending', 'accepted');
  return old;
end;
$$;

drop trigger if exists slots_before_delete on public.slots;
create trigger slots_before_delete before delete on public.slots
  for each row execute function public.slots_before_delete();

-- Admins may remove any slot
drop policy if exists "admins delete slots" on public.slots;
create policy "admins delete slots" on public.slots
  for delete to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Ratings: after a slot ends, the guest rates the host and the host rates the guest
-- ---------------------------------------------------------------------------
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings (id) on delete set null,
  slot_id uuid references public.slots (id) on delete set null,
  slot_title text not null default '',
  reviewer_id uuid not null references public.profiles (id) on delete cascade,
  reviewee_id uuid not null references public.profiles (id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  unique (booking_id, reviewer_id)
);

create index if not exists reviews_reviewee_idx on public.reviews (reviewee_id, created_at desc);

alter table public.reviews enable row level security;

drop policy if exists "members read reviews" on public.reviews;
create policy "members read reviews" on public.reviews
  for select to authenticated using (public.is_approved() or reviewer_id = auth.uid() or public.is_admin());

create or replace function public.submit_review(p_booking uuid, p_stars int, p_comment text default '')
returns public.reviews
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  s public.slots;
  target uuid;
  result public.reviews;
begin
  if not public.is_approved() then raise exception 'not approved'; end if;
  select * into b from public.bookings where id = p_booking;
  if b.id is null then raise exception 'booking not found'; end if;
  select * into s from public.slots where id = b.slot_id;
  if b.status <> 'accepted' then raise exception 'not accepted'; end if;
  if s.ends_at > now() then raise exception 'not finished'; end if;
  if auth.uid() = b.user_id then target := s.host_id;
  elsif auth.uid() = s.host_id then target := b.user_id;
  else raise exception 'not your booking';
  end if;
  if p_stars not between 1 and 5 then raise exception 'stars 1 to 5'; end if;

  insert into public.reviews (booking_id, slot_id, slot_title, reviewer_id, reviewee_id, stars, comment)
  values (b.id, s.id, s.title, auth.uid(), target, p_stars, left(coalesce(p_comment, ''), 500))
  on conflict (booking_id, reviewer_id) do update set stars = excluded.stars, comment = excluded.comment, created_at = now()
  returning * into result;

  perform public.notify(target, 'review_received', s.id, b.id);
  return result;
end;
$$;

-- Average stars and number of reviews for one member
create or replace function public.member_rating(p_user uuid, out rating numeric, out reviews int)
language sql stable security definer set search_path = public as $$
  select round(avg(stars)::numeric, 1), count(*)::int from public.reviews where reviewee_id = p_user;
$$;

-- ---------------------------------------------------------------------------
-- Member page
-- ---------------------------------------------------------------------------
create or replace function public.get_member(p_user uuid)
returns table (
  id uuid, full_name text, role public.member_role, area text, bio text, avatar_path text,
  member_since timestamptz, rating numeric, reviews int, hosted int, attended int
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_approved() or p_user = auth.uid() or public.is_admin()) then raise exception 'not approved'; end if;
  return query
    select p.id, p.full_name, p.role, p.area, p.bio, p.avatar_path, p.created_at,
           r.rating, r.reviews,
           (select count(*)::int from public.slots s where s.host_id = p.id),
           (select count(*)::int from public.bookings b join public.slots s on s.id = b.slot_id
             where b.user_id = p.id and b.status = 'accepted' and s.ends_at < now())
    from public.profiles p, public.member_rating(p.id) r
    where p.id = p_user and (p.status = 'approved' or p.id = auth.uid() or public.is_admin());
end;
$$;

create or replace function public.get_reviews(p_user uuid)
returns table (id uuid, stars int, comment text, created_at timestamptz, slot_title text, reviewer_id uuid, reviewer_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_approved() or p_user = auth.uid() or public.is_admin()) then raise exception 'not approved'; end if;
  return query
    select r.id, r.stars, r.comment, r.created_at, r.slot_title, r.reviewer_id, p.full_name
    from public.reviews r join public.profiles p on p.id = r.reviewer_id
    where r.reviewee_id = p_user
    order by r.created_at desc
    limit 100;
end;
$$;

-- ---------------------------------------------------------------------------
-- Feed and slot details, now with photos, location, host rating, search and dates.
-- Public pins are rounded to about 1 km; the exact spot shows with the address.
-- ---------------------------------------------------------------------------
drop function if exists public.get_feed(public.slot_kind[], text);
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
  photo_paths text[], lat double precision, lng double precision, host_rating numeric, host_reviews int
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_approved() then raise exception 'not approved'; end if;
  return query
    select s.id, s.host_id, p.full_name, s.kind, s.title, s.description, s.area, ''::text,
           s.starts_at, s.ends_at, s.capacity, public.slot_taken(s.id), s.price_egp, s.need_role,
           s.photo_path, s.is_open, s.photo_paths,
           round(s.lat::numeric, 2)::double precision, round(s.lng::numeric, 2)::double precision,
           r.rating, r.reviews
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
  exact_location boolean
)
language plpgsql stable security definer set search_path = public as $$
declare
  insider boolean;
begin
  if not (public.is_approved() or public.is_admin()
          or exists (select 1 from public.slots where slots.id = p_slot and slots.host_id = auth.uid())) then
    raise exception 'not approved';
  end if;
  -- The host, and people the host accepted, see the exact address, location and phone
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
           r.rating, r.reviews, insider
    from public.slots s
    join public.profiles p on p.id = s.host_id
    cross join lateral public.member_rating(s.host_id) r
    where s.id = p_slot;
end;
$$;

-- Host's request list, now saying whether the host has rated each person
drop function if exists public.get_slot_requests(uuid);
create function public.get_slot_requests(p_slot uuid)
returns table (
  id uuid, user_id uuid, status public.booking_status, message text, created_at timestamptz,
  full_name text, role public.member_role, phone text, price_egp int, fee_egp int,
  rating numeric, reviews int, reviewed boolean
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
           exists (select 1 from public.reviews v where v.booking_id = b.id and v.reviewer_id = auth.uid())
    from public.bookings b
    join public.profiles p on p.id = b.user_id
    cross join lateral public.member_rating(b.user_id) r
    where b.slot_id = p_slot
    order by b.created_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: suspend or reinstate a member, and an overview of the numbers
-- ---------------------------------------------------------------------------
create or replace function public.set_member_status(p_user uuid, p_suspend boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  if p_user = auth.uid() then raise exception 'not yourself'; end if;
  if p_suspend then
    update public.profiles set status = 'suspended', rejection_reason = left(p_reason, 300)
     where id = p_user and status = 'approved';
  else
    update public.profiles set status = 'approved', rejection_reason = null
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
    'waiting', (select count(*) from public.profiles where status = 'pending'),
    'suspended', (select count(*) from public.profiles where status::text = 'suspended'),
    'open_slots', (select count(*) from public.slots where is_open and starts_at > now()),
    'bookings_30d', (select count(*) from public.bookings where created_at > now() - interval '30 days'),
    'accepted_30d', (select count(*) from public.bookings where status = 'accepted' and updated_at > now() - interval '30 days'),
    'fees_30d', (select coalesce(sum(fee_egp), 0) from public.bookings where status = 'accepted' and updated_at > now() - interval '30 days')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Delete my account (required by the app stores). The app removes the person's files first.
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions for the new functions
-- ---------------------------------------------------------------------------
revoke execute on function public.get_feed, public.get_slot, public.get_slot_requests, public.submit_review,
  public.member_rating, public.get_member, public.get_reviews, public.set_member_status,
  public.admin_overview, public.delete_my_account from public, anon;
grant execute on function public.get_feed, public.get_slot, public.get_slot_requests, public.submit_review,
  public.member_rating, public.get_member, public.get_reviews, public.set_member_status,
  public.admin_overview, public.delete_my_account to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: profile photos, editing slot photos, removing your own files, size and type limits
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
 where id in ('verification', 'slot-photos', 'avatars');

drop policy if exists "manage own avatar" on storage.objects;
create policy "manage own avatar" on storage.objects
  for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "manage own slot photos" on storage.objects;
create policy "manage own slot photos" on storage.objects
  for all to authenticated
  using (bucket_id = 'slot-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'slot-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "delete own verification files" on storage.objects;
create policy "delete own verification files" on storage.objects
  for delete to authenticated
  using (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text);
