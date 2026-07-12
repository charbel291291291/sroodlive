-- Phase 5 local validation bootstrap (isolated supabase/postgres container).
-- The full 213-migration chain cannot be applied locally: a PRE-EXISTING legacy
-- migration (20260602122424_allow_room_owner_to_update_members.sql) references
-- public.room_members before it exists (known prod schema-drift), which aborts
-- `supabase start`/`db reset`. The agency V3 surface is self-contained, so it is
-- validated in isolation:
--
--   docker run -d --name agencytest -e POSTGRES_PASSWORD=postgres -p 55432:5432 \
--     public.ecr.aws/supabase/postgres:17.6.1.127
--   docker exec -i agencytest psql -U postgres < THIS_FILE
--   docker exec -i agencytest psql -U postgres < 20260711175349_agency_financial_foundation_v3.sql
--   docker exec -i agencytest psql -U postgres < 20260711181414_agency_finance_v3_rpc_implementation.sql
--   docker exec -i agencytest psql -U postgres < agency_phase5_executable_tests.sql
--
-- NOTE: this image's auth.uid() reads current_setting('request.jwt.claim.sub').
-- Production's auth.uid() reads the request.jwt.claims JSON; both are Supabase
-- official. The RPC code only calls auth.uid(), so it is agnostic. The test
-- harness sets request.jwt.claim.sub to impersonate an actor.
create table if not exists public._test_finance_admins(id uuid primary key);
create or replace function public.has_finance_access() returns boolean
language sql stable as $$ select coalesce(auth.uid() in (select id from public._test_finance_admins), false) $$;
insert into auth.users(id, instance_id, aud, role, email) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','creator@test'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','agent@test'),
 ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin@test')
on conflict (id) do nothing;
insert into public._test_finance_admins(id) values ('33333333-3333-3333-3333-333333333333') on conflict do nothing;
