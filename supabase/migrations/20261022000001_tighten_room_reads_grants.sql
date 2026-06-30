-- Tighten room_reads table grants.
-- Authenticated users should only SELECT their own rows via RLS.
-- Writes must go through RPC/security-definer functions.

REVOKE ALL ON TABLE public.room_reads FROM anon;
REVOKE ALL ON TABLE public.room_reads FROM authenticated;

GRANT SELECT ON TABLE public.room_reads TO authenticated;
