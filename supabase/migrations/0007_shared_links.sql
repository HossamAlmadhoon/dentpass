-- Shared slot links: anyone with the link sees the basics of an open slot before signing up.
-- No address, exact location, phone or InstaPay; those stay for accepted members.
create or replace function public.public_slot(p_slot uuid)
returns table (
  id uuid, host_name text, kind public.slot_kind, title text, description text, area text,
  starts_at timestamptz, ends_at timestamptz, capacity int, taken int, price_egp int,
  need_role public.member_role, negotiable boolean, photo_paths text[], host_rating numeric, host_reviews int
)
language sql stable security definer set search_path = public as $$
  select s.id, p.full_name, s.kind, s.title, s.description, s.area, s.starts_at, s.ends_at, s.capacity,
         public.slot_taken(s.id), s.price_egp, s.need_role, s.negotiable, s.photo_paths, r.rating, r.reviews
  from public.slots s
  join public.profiles p on p.id = s.host_id
  cross join lateral public.member_rating(s.host_id) r
  where s.id = p_slot and s.is_open and s.starts_at > now() and p.status = 'approved';
$$;

revoke execute on function public.public_slot from public;
grant execute on function public.public_slot to anon, authenticated;
