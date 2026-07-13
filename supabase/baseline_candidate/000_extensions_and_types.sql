-- =============================================================================
-- Baseline candidate 000 — extensions and enum types
-- Reconstructed verbatim from READ-ONLY production introspection (pg_extension,
-- pg_type/pg_enum). No production data. No secrets.
--
-- Production extensions (name version): pg_cron 1.6.4, pg_net 0.20.3,
--   pg_stat_statements 1.11, pgcrypto 1.3, plpgsql 1.0, supabase_vault 0.3.1,
--   uuid-ossp 1.1
-- Supabase-managed extensions (plpgsql, supabase_vault, pg_net,
--   pg_stat_statements) are provisioned by the platform image; guarded here so
--   the file is safe on any environment.
-- =============================================================================

create extension if not exists "uuid-ossp"  with schema extensions;
create extension if not exists "pgcrypto"   with schema extensions;
create extension if not exists "pg_cron";              -- schema cron (managed)
create extension if not exists "pg_net"     with schema extensions;
create extension if not exists "pg_stat_statements" with schema extensions;

-- ── Enum types (public) ──────────────────────────────────────────────────────
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                 where n.nspname='public' and t.typname='admin_permission') then
    create type public.admin_permission as enum (
      'users.read','users.write','psychologists.verify','content.publish',
      'academy.manage','community.moderate','support.manage','billing.manage',
      'settings.manage','audit.read');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                 where n.nspname='public' and t.typname='admin_task_status') then
    create type public.admin_task_status as enum (
      'open','in_progress','resolved','dismissed');
  end if;
end $$;
