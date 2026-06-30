begin;

select plan(24);

select ok(to_regclass('public.magic_srood_config') is not null,
  'Magic Srood config table exists');
select ok(to_regclass('public.magic_srood_global_rounds') is not null,
  'Magic Srood rounds table exists');
select ok(to_regclass('public.magic_srood_global_bets') is not null,
  'Magic Srood bets table exists');

select ok(to_regprocedure('public.get_or_create_magic_srood_round()') is not null,
  'round RPC exists');
select ok(to_regprocedure('public.place_magic_srood_global_bet(uuid,text,integer)') is not null,
  'bet RPC exists');
select ok(to_regprocedure('public.settle_magic_srood_global_round(uuid)') is not null,
  'settlement RPC exists');
select ok(to_regprocedure('public.get_magic_srood_team_totals(uuid)') is not null,
  'team totals RPC exists');
select ok(to_regprocedure('public.get_magic_srood_global_history(integer)') is not null,
  'history RPC exists');

select ok((select relrowsecurity from pg_class where oid = 'public.magic_srood_config'::regclass),
  'config RLS is enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.magic_srood_global_rounds'::regclass),
  'round RLS is enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.magic_srood_global_bets'::regclass),
  'bet RLS is enabled');

select ok(not has_table_privilege('anon', 'public.magic_srood_config', 'select'),
  'anonymous users cannot read config');
select ok(not has_table_privilege('anon', 'public.magic_srood_global_rounds', 'select'),
  'anonymous users cannot read rounds');
select ok(not has_table_privilege('authenticated', 'public.magic_srood_global_bets', 'insert'),
  'clients cannot insert bets directly');
select ok(not has_table_privilege('authenticated', 'public.magic_srood_global_rounds', 'update'),
  'clients cannot update rounds directly');
select ok(not has_table_privilege('authenticated', 'public.wallets', 'update'),
  'clients cannot update wallets directly');

select ok(not has_function_privilege('anon',
  'public.place_magic_srood_global_bet(uuid,text,integer)', 'execute'),
  'anonymous users cannot place bets');
select ok(has_function_privilege('authenticated',
  'public.place_magic_srood_global_bet(uuid,text,integer)', 'execute'),
  'authenticated users can place bets through the RPC');
select ok(not has_function_privilege('anon',
  'public.settle_magic_srood_global_round(uuid)', 'execute'),
  'anonymous users cannot request settlement');

select ok((select prosecdef from pg_proc
  where oid = 'public.place_magic_srood_global_bet(uuid,text,integer)'::regprocedure),
  'bet RPC is SECURITY DEFINER');
select ok((select prosecdef from pg_proc
  where oid = 'public.settle_magic_srood_global_round(uuid)'::regprocedure),
  'settlement RPC is SECURITY DEFINER');
select ok((select proconfig @> array['search_path=""']::text[] from pg_proc
  where oid = 'public.place_magic_srood_global_bet(uuid,text,integer)'::regprocedure),
  'bet RPC has an empty search path');
select ok((select proconfig @> array['search_path=""']::text[] from pg_proc
  where oid = 'public.settle_magic_srood_global_round(uuid)'::regprocedure),
  'settlement RPC has an empty search path');

select ok(exists (
  select 1
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'magic_srood_global_bets'
    and indexname = 'magic_srood_bets_round_status_idx'
), 'round settlement index exists');

select * from finish();
rollback;
