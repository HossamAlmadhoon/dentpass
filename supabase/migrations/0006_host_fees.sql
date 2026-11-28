-- DentPass fee moves to the host. Guests pay the listed price, nothing added.
-- The host owes DentPass a share of each confirmed booking (fee_percent), settled monthly by InstaPay.
-- The pilot starts free: fee_percent = 0.

update public.app_settings set fee_percent = 0;
alter table public.app_settings alter column fee_percent set default 0;

-- bookings.fee_egp now means: what the host owes DentPass for this booking.
-- It is worked out when the host accepts, at the fee in force then.
update public.bookings set fee_egp = 0 where status <> 'accepted';

create or replace function public.respond_booking(p_booking uuid, p_accept boolean)
returns public.bookings
language plpgsql security definer set search_path = public as $$
declare
  b public.bookings;
  s public.slots;
  accepted int;
  fee numeric;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b.id is null then raise exception 'booking not found'; end if;
  select * into s from public.slots where id = b.slot_id for update;
  if s.host_id <> auth.uid() then raise exception 'not your slot'; end if;
  if b.status <> 'pending' then raise exception 'already answered'; end if;

  if p_accept then
    select count(*) into accepted from public.bookings where slot_id = s.id and status = 'accepted';
    if accepted >= s.capacity then raise exception 'slot full'; end if;
    select fee_percent into fee from public.app_settings;
    update public.bookings
       set status = 'accepted', updated_at = now(),
           fee_egp = case when s.kind = 'cover' then 0 else round(b.price_egp * coalesce(fee, 0) / 100) end
     where id = b.id returning * into b;
    perform public.notify(b.user_id, 'booking_accepted', s.id, b.id);
  else
    update public.bookings set status = 'declined', fee_egp = 0, updated_at = now() where id = b.id returning * into b;
    perform public.notify(b.user_id, 'booking_declined', s.id, b.id);
  end if;
  return b;
end;
$$;

-- A booking that is cancelled no longer owes anything
create or replace function public.bookings_clear_fee()
returns trigger language plpgsql as $$
begin
  if new.status in ('cancelled', 'declined') then new.fee_egp := 0; end if;
  return new;
end;
$$;
drop trigger if exists bookings_clear_fee on public.bookings;
create trigger bookings_clear_fee before update of status on public.bookings
  for each row execute function public.bookings_clear_fee();

-- ---------------------------------------------------------------------------
-- Monthly settling: the host says "paid", an admin confirms
-- ---------------------------------------------------------------------------
create table if not exists public.fee_settlements (
  host_id uuid not null references public.profiles (id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  amount_egp int not null default 0,
  host_paid_at timestamptz,
  confirmed_at timestamptz,
  primary key (host_id, month)
);
alter table public.fee_settlements enable row level security;
drop policy if exists "hosts read own settlements" on public.fee_settlements;
create policy "hosts read own settlements" on public.fee_settlements
  for select to authenticated using (host_id = auth.uid() or public.is_admin());

-- What a host owes, month by month (bookings that took place in that month)
create or replace function public.host_statement()
returns table (month date, bookings int, earned_egp int, fee_egp int, host_paid_at timestamptz, confirmed_at timestamptz)
language sql stable security definer set search_path = public as $$
  with m as (
    select date_trunc('month', s.starts_at at time zone 'Africa/Cairo')::date as month,
           count(*)::int as bookings, sum(b.price_egp)::int as earned, sum(b.fee_egp)::int as fee
    from public.bookings b
    join public.slots s on s.id = b.slot_id
    where s.host_id = auth.uid() and b.status = 'accepted'
    group by 1
  )
  select m.month, m.bookings, m.earned, m.fee, f.host_paid_at, f.confirmed_at
  from m left join public.fee_settlements f on f.host_id = auth.uid() and f.month = m.month
  order by m.month desc
  limit 24;
$$;

create or replace function public.mark_fees_paid(p_month date)
returns void language plpgsql security definer set search_path = public as $$
declare
  owed int;
begin
  select coalesce(sum(b.fee_egp), 0) into owed
  from public.bookings b join public.slots s on s.id = b.slot_id
  where s.host_id = auth.uid() and b.status = 'accepted'
    and date_trunc('month', s.starts_at at time zone 'Africa/Cairo')::date = p_month;
  if owed <= 0 then raise exception 'nothing owed'; end if;
  insert into public.fee_settlements (host_id, month, amount_egp, host_paid_at)
  values (auth.uid(), p_month, owed, now())
  on conflict (host_id, month) do update set amount_egp = excluded.amount_egp, host_paid_at = now()
    where public.fee_settlements.confirmed_at is null;
end;
$$;

-- Admin: every host's fees per month, and confirming money arrived
create or replace function public.admin_fees()
returns table (host_id uuid, full_name text, phone text, month date, bookings int, fee_egp int,
               host_paid_at timestamptz, confirmed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  return query
    with m as (
      select s.host_id, date_trunc('month', s.starts_at at time zone 'Africa/Cairo')::date as month,
             count(*)::int as bookings, sum(b.fee_egp)::int as fee
      from public.bookings b join public.slots s on s.id = b.slot_id
      where b.status = 'accepted'
      group by 1, 2
    )
    select m.host_id, p.full_name, p.phone, m.month, m.bookings, m.fee, f.host_paid_at, f.confirmed_at
    from m
    join public.profiles p on p.id = m.host_id
    left join public.fee_settlements f on f.host_id = m.host_id and f.month = m.month
    where m.fee > 0
    order by (f.confirmed_at is not null), m.month desc, p.full_name
    limit 300;
end;
$$;

create or replace function public.confirm_fees(p_host uuid, p_month date)
returns void language plpgsql security definer set search_path = public as $$
declare
  owed int;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select coalesce(sum(b.fee_egp), 0) into owed
  from public.bookings b join public.slots s on s.id = b.slot_id
  where s.host_id = p_host and b.status = 'accepted'
    and date_trunc('month', s.starts_at at time zone 'Africa/Cairo')::date = p_month;
  insert into public.fee_settlements (host_id, month, amount_egp, confirmed_at)
  values (p_host, p_month, owed, now())
  on conflict (host_id, month) do update set amount_egp = excluded.amount_egp, confirmed_at = now();
end;
$$;

-- Admins can also change DentPass's own InstaPay (instapay_handle) and the fee in Settings (existing policy).

revoke execute on function public.respond_booking, public.host_statement, public.mark_fees_paid,
  public.admin_fees, public.confirm_fees from public, anon;
grant execute on function public.respond_booking, public.host_statement, public.mark_fees_paid,
  public.admin_fees, public.confirm_fees to authenticated;
