-- DentPass version 3 database update.
-- Safe on the live project: version 2 of the app keeps working with it.

-- ---------------------------------------------------------------------------
-- Members: language for phone notifications, and when they accepted the terms
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists lang text not null default 'ar' check (lang in ('ar', 'en')),
  add column if not exists accepted_terms_at timestamptz;

-- ---------------------------------------------------------------------------
-- Settings admins can change in the app: the fee and the support WhatsApp number
-- ---------------------------------------------------------------------------
alter table public.app_settings add column if not exists support_whatsapp text check (char_length(support_whatsapp) <= 30);

drop policy if exists "admins update settings" on public.app_settings;
create policy "admins update settings" on public.app_settings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Reports: a member reports another member or a slot; admins review them
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  member_id uuid references public.profiles (id) on delete cascade,
  slot_id uuid references public.slots (id) on delete set null,
  slot_title text not null default '',
  reason text not null check (reason in ('no_show', 'unsafe', 'fake', 'payment', 'behaviour', 'other')),
  details text not null default '' check (char_length(details) <= 1000),
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check (member_id is not null or slot_id is not null)
);

create index if not exists reports_open_idx on public.reports (status, created_at desc);

alter table public.reports enable row level security;

drop policy if exists "members report" on public.reports;
create policy "members report" on public.reports
  for insert to authenticated
  with check (reporter_id = auth.uid() and public.is_approved() and status = 'open' and member_id is distinct from auth.uid());

drop policy if exists "read own reports or admin" on public.reports;
create policy "read own reports or admin" on public.reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_admin());

drop policy if exists "admins close reports" on public.reports;
create policy "admins close reports" on public.reports
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.reports_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.slot_id is not null and new.slot_title = '' then
    update public.reports set slot_title = coalesce((select title from public.slots where id = new.slot_id), '') where id = new.id;
  end if;
  insert into public.notifications (user_id, type, slot_id)
  select p.id, 'report_received', new.slot_id from public.profiles p where p.is_admin;
  return null;
end;
$$;

drop trigger if exists reports_after_insert on public.reports;
create trigger reports_after_insert after insert on public.reports
  for each row execute function public.reports_after_insert();

-- Admins see who reported whom
create or replace function public.admin_reports(p_status text default 'open')
returns table (
  id uuid, reason text, details text, status text, created_at timestamptz,
  reporter_id uuid, reporter_name text, member_id uuid, member_name text, slot_id uuid, slot_title text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  return query
    select r.id, r.reason, r.details, r.status, r.created_at,
           r.reporter_id, rp.full_name, r.member_id, mp.full_name, r.slot_id, r.slot_title
    from public.reports r
    join public.profiles rp on rp.id = r.reporter_id
    left join public.profiles mp on mp.id = r.member_id
    where r.status = p_status
    order by r.created_at desc
    limit 200;
end;
$$;

-- ---------------------------------------------------------------------------
-- Alerts: "tell me about new slots like this" (types and area)
-- ---------------------------------------------------------------------------
create table if not exists public.slot_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  kinds public.slot_kind[],
  area text,
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, kinds, area)
);

alter table public.slot_alerts enable row level security;

drop policy if exists "own alerts" on public.slot_alerts;
create policy "own alerts" on public.slot_alerts
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_approved());

create or replace function public.slots_alert_matches()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, type, slot_id)
  select distinct a.user_id, 'new_slot', new.id
  from public.slot_alerts a
  join public.profiles p on p.id = a.user_id and p.status = 'approved'
  where a.user_id <> new.host_id
    and (a.kinds is null or new.kind = any (a.kinds))
    and (a.area is null or a.area = new.area);
  return null;
end;
$$;

drop trigger if exists slots_alert_matches on public.slots;
create trigger slots_alert_matches after insert on public.slots
  for each row execute function public.slots_alert_matches();

-- ---------------------------------------------------------------------------
-- Home screen: my next accepted slot, and how many requests wait for me as a host
-- ---------------------------------------------------------------------------
create or replace function public.my_home()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  next_slot json;
begin
  if not public.is_approved() then raise exception 'not approved'; end if;
  select json_build_object('booking_id', b.id, 'slot_id', s.id, 'title', s.title, 'kind', s.kind,
                           'starts_at', s.starts_at, 'ends_at', s.ends_at, 'area', s.area, 'address', s.address,
                           'lat', s.lat, 'lng', s.lng, 'host_name', p.full_name, 'host_phone', p.phone)
    into next_slot
  from public.bookings b
  join public.slots s on s.id = b.slot_id
  join public.profiles p on p.id = s.host_id
  where b.user_id = auth.uid() and b.status = 'accepted' and s.ends_at > now()
  order by s.starts_at
  limit 1;

  return json_build_object(
    'next', next_slot,
    'waiting', (select count(*) from public.bookings b join public.slots s on s.id = b.slot_id
                 where s.host_id = auth.uid() and b.status = 'pending' and s.ends_at > now()),
    'hosting_next', (select json_build_object('slot_id', s.id, 'title', s.title, 'starts_at', s.starts_at,
                                              'accepted', (select count(*) from public.bookings b
                                                           where b.slot_id = s.id and b.status = 'accepted'))
                     from public.slots s where s.host_id = auth.uid() and s.ends_at > now()
                     order by s.starts_at limit 1)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Reminders the day before, sent every hour by the scheduler
-- ---------------------------------------------------------------------------
alter table public.bookings add column if not exists reminded_at timestamptz;
alter table public.slots add column if not exists host_reminded_at timestamptz;

create or replace function public.send_reminders()
returns int language plpgsql security definer set search_path = public as $$
declare
  sent int := 0;
  n int;
begin
  -- People going: one reminder per booking, for slots starting in the next 1 to 26 hours
  with due as (
    update public.bookings b set reminded_at = now()
    from public.slots s
    where s.id = b.slot_id and b.status = 'accepted' and b.reminded_at is null
      and s.starts_at between now() + interval '1 hour' and now() + interval '26 hours'
    returning b.id, b.user_id, b.slot_id
  )
  insert into public.notifications (user_id, type, slot_id, booking_id)
  select user_id, 'reminder', slot_id, id from due;
  get diagnostics n = row_count;
  sent := sent + n;

  -- Hosts: one reminder per slot that has someone accepted
  with due as (
    update public.slots s set host_reminded_at = now()
    where s.host_reminded_at is null
      and s.starts_at between now() + interval '1 hour' and now() + interval '26 hours'
      and exists (select 1 from public.bookings b where b.slot_id = s.id and b.status = 'accepted')
    returning s.id, s.host_id
  )
  insert into public.notifications (user_id, type, slot_id)
  select host_id, 'host_reminder', id from due;
  get diagnostics n = row_count;
  return sent + n;
end;
$$;

revoke execute on function public.send_reminders() from public, anon, authenticated;

create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'dentpass-reminders') then
    perform cron.unschedule('dentpass-reminders');
  end if;
  perform cron.schedule('dentpass-reminders', '5 * * * *', 'select public.send_reminders()');
end;
$$;

-- ---------------------------------------------------------------------------
-- Phone notifications (web push). The app saves each device's subscription;
-- every new notification asks the send-push function to deliver it.
-- ---------------------------------------------------------------------------
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) <= 1000),
  p256dh text not null check (char_length(p256dh) <= 200),
  auth text not null check (char_length(auth) <= 100),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

alter table public.push_subscriptions enable row level security;

drop policy if exists "own devices" on public.push_subscriptions;
create policy "own devices" on public.push_subscriptions
  for select to authenticated using (user_id = auth.uid());

-- A shared phone moves to whoever signed in last
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_lang text default 'ar')
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_endpoint !~ '^https://' then raise exception 'bad endpoint'; end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth, created_at = now();
  update public.profiles set lang = case when p_lang = 'en' then 'en' else 'ar' end where id = auth.uid();
end;
$$;

create or replace function public.remove_push_subscription(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

alter table public.notifications add column if not exists pushed_at timestamptz;

-- Where the sending function lives. Not readable through the app's API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.config (key text primary key, value text not null);
insert into private.config (key, value)
values ('push_url', 'https://ezfhozjfegtcyrwmvqpc.supabase.co/functions/v1/send-push')
on conflict (key) do nothing;

create extension if not exists pg_net with schema extensions;

create or replace function public.notifications_push_hook()
returns trigger language plpgsql security definer set search_path = public, private, extensions as $$
declare
  target text;
begin
  if not exists (select 1 from public.push_subscriptions where user_id = new.user_id) then
    return null;
  end if;
  select value into target from private.config where key = 'push_url';
  if target is null or target = '' then return null; end if;
  perform net.http_post(
    url := target,
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  return null;
end;
$$;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications
  for each row execute function public.notifications_push_hook();

-- ---------------------------------------------------------------------------
-- Permissions for the new functions
-- ---------------------------------------------------------------------------
revoke execute on function public.admin_reports, public.my_home, public.save_push_subscription,
  public.remove_push_subscription from public, anon;
grant execute on function public.admin_reports, public.my_home, public.save_push_subscription,
  public.remove_push_subscription to authenticated;
