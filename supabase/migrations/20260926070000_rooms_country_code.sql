-- ============================================================
-- Add country_code to rooms for server-side country filtering
-- ============================================================
-- Existing rooms are backfilled from their owner's profile.country_code.
-- New rooms get country_code from the insert call (Flutter passes it).
-- The column is nullable so rooms with unknown country remain visible
-- under "All countries" but are excluded from any specific country filter.
-- ============================================================

-- 1. Add column
alter table public.rooms
  add column if not exists country_code text;

-- 2. Backfill existing rooms from owner profile
update public.rooms r
set    country_code = upper(trim(p.country_code))
from   public.profiles p
where  p.id          = r.owner_id
  and  p.country_code is not null
  and  trim(p.country_code) <> ''
  and  r.country_code is null;

-- 3. Index for fast per-country queries
create index if not exists idx_rooms_country_code
  on public.rooms (country_code)
  where country_code is not null;
