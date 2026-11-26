-- DentPass: initial schema for Supabase (Postgres 15+)
-- Run in the Supabase SQL editor, or with `supabase db push`.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.slot_kind as enum ('observe', 'course', 'rent', 'cover');
create type public.verification_status as enum ('unverified', 'pending', 'approved', 'rejected');
create type public.booking_status as enum ('pending', 'accepted', 'declined', 'cancelled');
create type public.member_role as enum ('dentist', 'assistant');

-- ---------------------------------------------------------------------------
-- Settings (one row). fee_percent is DentPass's service fee on each booking.
-- ---------------------------------------------------------------------------
create table public.app_settings (
  id boolean primary key default true check (id),
  fee_percent numeric(5, 2) not null default 10 check (fee_percent >= 0 and fee_percent <= 50),
  instapay_handle text
);
insert into public.app_settings (id) values (true);

-- ---------------------------------------------------------------------------
-- Profiles: one per signed-up user
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '' check (char_length(full_name) <= 120),
  phone text check (char_length(phone) <= 30),
  role public.member_role not null default 'dentist',
  syndicate_no text check (char_length(syndicate_no) <= 40),
  area text check (char_length(area) <= 60),
  status public.verification_status not null default 'unverified',
  rejection_reason text check (char_length(rejection_reason) <= 300),
  card_path text,   -- syndicate card image in the private "verification" bucket
  id_path text,     -- national ID image in the private "verification" bucket
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  submitted_at timestamptz
);

-- Create a profile automatically when someone signs up
create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Helper checks used by policies and functions
create function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create function public.is_approved()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'approved' from public.profiles where id = auth.uid()), false);
$$;

-- People may edit their own details, but never their own status or admin flag.
-- The only status change they may make is submitting for review.
create function public.protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() or auth.uid() is null then
    return new;  -- admins, and server-side code without a user, may change anything
  end if;
  if new.is_admin is distinct from old.is_admin then
    raise exception 'not allowed to change admin flag';
  end if;
  -- Once submitted, the checked details are locked until an admin rejects them
  if old.status in ('pending', 'approved') and (
       new.role is distinct from old.role
       or new.syndicate_no is distinct from old.syndicate_no
       or new.card_path is distinct from old.card_path
       or new.id_path is distinct from old.id_path
       or new.full_name is distinct from old.full_name) then
    raise exception 'checked details are locked';
  end if;
  if new.status is distinct from old.status then
    if not (old.status in ('unverified', 'rejected') and new.status = 'pending') then
      raise exception 'not allowed to change verification status';
    end if;
    if new.id_path is null or (new.role = 'dentist' and (new.card_path is null or new.syndicate_no is null)) then
      raise exception 'documents missing';
    end if;
    new.submitted_at := now();
    new.rejection_reason := null;
  end if;
  return new;
end;
$$;

create trigger profiles_protect
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

alter table public.profiles enable row level security;

create policy "read own profile or admin" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());

create policy "update own profile" on public.profiles
  for update to authenticated using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Public card for other members: name, role and area only (no phone, no documents)
create view public.public_profiles
with (security_barrier = true) as
  select id, full_name, role, area
  from public.profiles
  where status = 'approved';

revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Slots: what hosts post
-- ---------------------------------------------------------------------------
create table public.slots (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles (id) on delete cascade,
  kind public.slot_kind not null,
  title text not null check (char_length(title) between 3 and 120),
  description text not null default '' check (char_length(description) <= 2000),
  area text not null check (char_length(area) <= 60),
  address text not null default '' check (char_length(address) <= 300),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity int not null default 1 check (capacity between 1 and 100),
  price_egp int not null default 0 check (price_egp between 0 and 1000000),
  need_role public.member_role,               -- only for kind = 'cover'
  photo_path text,                            -- in the public "slot-photos" bucket
  is_open boolean not null default true,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check ((kind = 'cover') = (need_role is not null))
);

create index slots_feed_idx on public.slots (is_open, starts_at);
create index slots_host_idx on public.slots (host_id);

alter table public.slots enable row level security;

create policy "approved members read slots" on public.slots
  for select to authenticated using (public.is_approved() or host_id = auth.uid() or public.is_admin());

create policy "approved members post slots" on public.slots
  for insert to authenticated
  with check (host_id = auth.uid() and public.is_approved() and starts_at > now());

create policy "hosts edit own slots" on public.slots
  for update to authenticated using (host_id = auth.uid()) with check (host_id = auth.uid());

create policy "hosts delete own slots" on public.slots
  for delete to authenticated using (host_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Bookings: a request to take a seat, rent a chair or cover a shift
-- ---------------------------------------------------------------------------
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.slots (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status public.booking_status not null default 'pending',
  message text not null default '' check (char_length(message) <= 500),
  price_egp int not null,
  fee_egp int not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (slot_id, user_id)
);

create index bookings_user_idx on public.bookings (user_id);

alter table public.bookings enable row level security;

-- Read: your own bookings, and bookings on slots you host. All writes go through functions below.
create policy "read own or hosted bookings" on public.bookings
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.slots s where s.id = slot_id and s.host_id = auth.uid())
    or public.is_admin()
  );

-- ---------------------------------------------------------------------------
-- Notifications (in-app). The app turns `type` into a sentence in the user's language.
-- ---------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,  -- booking_requested | booking_accepted | booking_declined | booking_cancelled | verification_approved | verification_rejected
  slot_id uuid references public.slots (id) on delete cascade,
  booking_id uuid references public.bookings (id) on delete cascade,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

create policy "read own notifications" on public.notifications
  for select to authenticated using (user_id = auth.uid());

create policy "mark own notifications read" on public.notifications
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Feed: slots with host name and places taken, for approved members
-- ---------------------------------------------------------------------------
create function public.slot_taken(p_slot uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.bookings
  where slot_id = p_slot
    and status = any (case when (select kind from public.slots where id = p_slot) = 'cover'
                           then array['accepted']::public.booking_status[]
                           else array['pending', 'accepted']::public.booking_status[] end);
$$;

create function public.get_feed(p_kind public.slot_kind[] default null, p_area text default null)
returns table (
  id uuid, host_id uuid, host_name text, kind public.slot_kind, title text, description text,
  area text, address text, starts_at timestamptz, ends_at timestamptz, capacity int, taken int,
  price_egp int, need_role public.member_role, photo_path text, is_open boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_approved() then
    raise exception 'not approved';
  end if;
  return query
    select s.id, s.host_id, p.full_name, s.kind, s.title, s.description, s.area, s.address,
           s.starts_at, s.ends_at, s.capacity, public.slot_taken(s.id), s.price_egp, s.need_role,
           s.photo_path, s.is_open
    from public.slots s
    join public.profiles p on p.id = s.host_id
    where s.is_open
      and s.starts_at > now()
      and (p_kind is null or s.kind = any (p_kind))
      and (p_area is null or s.area = p_area)
    order by s.starts_at
    limit 200;
end;
$$;

create function public.get_slot(p_slot uuid)
returns table (
  id uuid, host_id uuid, host_name text, kind public.slot_kind, title text, description text,
  area text, address text, starts_at timestamptz, ends_at timestamptz, capacity int, taken int,
  price_egp int, need_role public.member_role, photo_path text, is_open boolean, host_phone text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_approved() or exists (select 1 from public.slots where slots.id = p_slot and slots.host_id = auth.uid())) then
    raise exception 'not approved';
  end if;
  return query
    select s.id, s.host_id, p.full_name, s.kind, s.title, s.description, s.area,
           -- the exact address is shown only to the host and to people with an accepted booking
           case when s.host_id = auth.uid() or exists (
                  select 1 from public.bookings b where b.slot_id = s.id and b.user_id = auth.uid() and b.status = 'accepted')
                then s.address else '' end,
           s.starts_at, s.ends_at, s.capacity, public.slot_taken(s.id), s.price_egp, s.need_role,
           s.photo_path, s.is_open,
           -- the host's phone, likewise, only once your booking is accepted
           case when exists (
                  select 1 from public.bookings b where b.slot_id = s.id and b.user_id = auth.uid() and b.status = 'accepted')
                then p.phone else null end
    from public.slots s
    join public.profiles p on p.id = s.host_id
    where s.id = p_slot;
end;
$$;

-- ---------------------------------------------------------------------------
-- Booking actions
-- ---------------------------------------------------------------------------
create function public.notify(p_user uuid, p_type text, p_slot uuid, p_booking uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, type, slot_id, booking_id) values (p_user, p_type, p_slot, p_booking);
$$;

-- Request a place. Seats and chairs are held while the request is pending; cover offers are not limited.
create function public.book_slot(p_slot uuid, p_message text default '')
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  s public.slots;
  me public.profiles;
  fee numeric;
  result public.bookings;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or me.status <> 'approved' then raise exception 'not approved'; end if;

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

-- Host accepts or declines a request
create function public.respond_booking(p_booking uuid, p_accept boolean)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  s public.slots;
  accepted int;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b.id is null then raise exception 'booking not found'; end if;
  select * into s from public.slots where id = b.slot_id for update;
  if s.host_id <> auth.uid() then raise exception 'not your slot'; end if;
  if b.status <> 'pending' then raise exception 'already answered'; end if;

  if p_accept then
    select count(*) into accepted from public.bookings where slot_id = s.id and status = 'accepted';
    if accepted >= s.capacity then raise exception 'slot full'; end if;
    update public.bookings set status = 'accepted', updated_at = now() where id = b.id returning * into b;
    perform public.notify(b.user_id, 'booking_accepted', s.id, b.id);
  else
    update public.bookings set status = 'declined', updated_at = now() where id = b.id returning * into b;
    perform public.notify(b.user_id, 'booking_declined', s.id, b.id);
  end if;
  return b;
end;
$$;

-- The person who booked cancels
create function public.cancel_booking(p_booking uuid)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  s public.slots;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b.id is null or b.user_id <> auth.uid() then raise exception 'booking not found'; end if;
  if b.status not in ('pending', 'accepted') then raise exception 'cannot cancel'; end if;
  update public.bookings set status = 'cancelled', updated_at = now() where id = b.id returning * into b;
  select * into s from public.slots where id = b.slot_id;
  perform public.notify(s.host_id, 'booking_cancelled', s.id, b.id);
  return b;
end;
$$;

-- Host sees the requests on one of their slots. Phone numbers show once a request is accepted.
create function public.get_slot_requests(p_slot uuid)
returns table (
  id uuid, user_id uuid, status public.booking_status, message text, created_at timestamptz,
  full_name text, role public.member_role, phone text, price_egp int, fee_egp int
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from public.slots s where s.id = p_slot and s.host_id = auth.uid()) then
    raise exception 'not your slot';
  end if;
  return query
    select b.id, b.user_id, b.status, b.message, b.created_at, p.full_name, p.role,
           case when b.status = 'accepted' then p.phone else null end, b.price_egp, b.fee_egp
    from public.bookings b
    join public.profiles p on p.id = b.user_id
    where b.slot_id = p_slot
    order by b.created_at;
end;
$$;

-- Admin approves or rejects a member's documents
create function public.set_verification(p_user uuid, p_approve boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  update public.profiles
     set status = case when p_approve then 'approved'::public.verification_status else 'rejected'::public.verification_status end,
         rejection_reason = case when p_approve then null else left(p_reason, 300) end
   where id = p_user and status = 'pending';
  if not found then raise exception 'nothing to review'; end if;
  perform public.notify(p_user, case when p_approve then 'verification_approved' else 'verification_rejected' end, null, null);
end;
$$;

-- Only signed-in users may call the functions
revoke execute on function public.get_feed, public.get_slot, public.get_slot_requests, public.book_slot, public.respond_booking,
  public.cancel_booking, public.set_verification, public.notify, public.slot_taken from public, anon;
grant execute on function public.get_feed, public.get_slot, public.get_slot_requests, public.book_slot, public.respond_booking,
  public.cancel_booking, public.set_verification, public.slot_taken to authenticated;

-- Settings are readable by members (the app shows the fee), editable only from the dashboard
alter table public.app_settings enable row level security;
create policy "members read settings" on public.app_settings for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Storage buckets
-- Files are stored under "<user id>/<file name>".
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('verification', 'verification', false)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('slot-photos', 'slot-photos', true)
  on conflict (id) do nothing;

create policy "upload own verification files" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "replace own verification files" on storage.objects
  for update to authenticated
  using (bucket_id = 'verification' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "read own verification files or admin" on storage.objects
  for select to authenticated
  using (bucket_id = 'verification' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

create policy "upload own slot photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'slot-photos' and (storage.foldername(name))[1] = auth.uid()::text);
