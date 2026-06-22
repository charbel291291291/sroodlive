-- Phase R4-B: server-side aggregate for active member counts
--
-- Problem: getActiveMemberCounts() issued a SELECT on ALL room_members rows
-- with left_at IS NULL, then grouped them in Dart. As the table grows this
-- becomes a full index scan returning every active member row to the client
-- just to be counted — wasted bandwidth and CPU on both sides.
--
-- Fix: push the GROUP BY into Postgres. The client sends only the room IDs it
-- already has (from getRooms), and the DB returns one row per room.
--
-- Performance: query touches only the rows for the requested rooms thanks to
-- the equality filter on room_id. With an index on (room_id, left_at,
-- last_seen_at) Postgres can satisfy the query with an index-only scan.

-- ── Optional supporting index (safe to create concurrently in production) ────
-- Covers: room_id = any(...) AND left_at IS NULL AND last_seen_at >= threshold
create index if not exists room_members_active_lookup_idx
  on public.room_members (room_id, last_seen_at)
  where left_at is null;

-- ── RPC ──────────────────────────────────────────────────────────────────────
create or replace function public.get_active_member_counts(
  p_room_ids uuid[]
)
returns table (room_id uuid, active_count integer)
language sql
security definer
stable
set search_path = public
as $$
  -- Empty input returns zero rows without touching any data.
  select
    rm.room_id,
    count(*)::integer as active_count
  from public.room_members rm
  where rm.room_id = any(p_room_ids)
    and rm.left_at is null
    and rm.last_seen_at >= now() - interval '45 seconds'
  group by rm.room_id;
$$;

grant execute on function public.get_active_member_counts(uuid[]) to authenticated;

comment on function public.get_active_member_counts(uuid[]) is
  'Returns active member counts grouped by room_id for the requested rooms only. '
  'Active = left_at IS NULL AND last_seen_at within the last 45 seconds. '
  'Replaces the client-side full-scan aggregation in getActiveMemberCounts().';
