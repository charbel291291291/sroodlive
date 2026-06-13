-- ────────────────────────────────────────────────────────────────────────────
-- Enable Supabase Realtime for room gifts & members
--
--   The app drives live gift animations and seat/member updates through
--   `onPostgresChanges`, but these tables were never added to the
--   `supabase_realtime` publication. As a result the realtime stream never
--   fired on other devices: a gift was charged and recorded, yet only the
--   sender saw the animation — receivers got nothing.
--
--   This adds both tables to the publication and sets REPLICA IDENTITY FULL so
--   UPDATE/DELETE payloads carry the room_id needed by the client-side filters
--   (e.g. mute/seat changes and leave events on room_members).
-- ────────────────────────────────────────────────────────────────────────────

-- gift_transactions: insert events power the gift overlay for every member.
alter publication supabase_realtime add table public.gift_transactions;

-- room_members: seat / mute / join / leave updates for the live seat UI.
alter publication supabase_realtime add table public.room_members;

alter table public.gift_transactions replica identity full;
alter table public.room_members replica identity full;
