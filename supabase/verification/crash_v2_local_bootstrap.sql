-- Crash Rocket v2 — local validation bootstrap (isolated container / stack).
-- Creates three test identities (player A, player B, admin), wallets, and
-- enables the v2 feature flag FOR LOCAL TESTS ONLY (production ships disabled).
--
-- NOTE: the local supabase/postgres image's auth.uid() reads
-- current_setting('request.jwt.claim.sub'); the harness impersonates actors by
-- setting that GUC (same approach validated by the Agency V3 suite).

insert into auth.users (id, instance_id, aud, role, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','00000000-0000-0000-0000-000000000000','authenticated','authenticated','crash_a@test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','00000000-0000-0000-0000-000000000000','authenticated','authenticated','crash_b@test'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','00000000-0000-0000-0000-000000000000','authenticated','authenticated','crash_admin@test')
on conflict (id) do nothing;

insert into public.profiles (id, display_name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Crash Tester A'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Crash Tester B'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Crash Admin')
on conflict (id) do nothing;

insert into public.wallets (user_id, coins_balance) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1000000),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1000000),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 1000000)
on conflict (user_id) do update set coins_balance = excluded.coins_balance;

insert into public.admin_users (user_id, role, display_name, is_active) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'o_super_admin', 'Crash Admin', true)
on conflict do nothing;

-- Local-only: enable the game so the engine can run. Production stays false.
update public.game_settings set is_enabled = true
where game_key = 'crash_rocket_v2';
