-- Allow authenticated clients to read their own room_reads through RLS.
-- Keep anon blocked.

REVOKE ALL ON TABLE public.room_reads FROM anon;
GRANT SELECT ON TABLE public.room_reads TO authenticated;
