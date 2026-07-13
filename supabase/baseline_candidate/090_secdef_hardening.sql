-- Baseline 090 — SECURITY DEFINER search_path hardening (deliberate deviation).
-- Production has 2 SECURITY DEFINER functions with no fixed search_path; pin them
-- to pg_catalog,public. Behaviour-preserving (both operate on public objects);
-- closes a search_path-injection surface. This is the ONLY intentional
-- difference between the candidate baseline and production.
alter function public.handle_new_user_game_wallet() set search_path = pg_catalog, public;
alter function public.vip_privilege_active(uuid, text) set search_path = pg_catalog, public;
