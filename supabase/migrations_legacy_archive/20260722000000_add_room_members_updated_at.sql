-- Migration: add updated_at column to room_members
--
-- Root cause: RPCs remove_room_member, update_room_member_role,
-- update_room_member_seat, and owner_mute_member all write
-- "updated_at = now()" to public.room_members, but the table was
-- originally created without that column, causing PostgrestException
-- code 42703 on every moderation action (mute, kick, remove from mic).
--
-- Idempotent: "add column if not exists" + CREATE OR REPLACE are safe to re-run.

-- ── 1. Add the column ─────────────────────────────────────────────────────────
-- DEFAULT NOW() automatically sets the value for all existing rows on add.
alter table public.room_members
  add column if not exists updated_at timestamptz not null default now();

-- ── 2. Auto-update trigger function ──────────────────────────────────────────
create or replace function public.set_updated_at_room_members()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ── 3. Attach trigger (drop first so re-runs are safe) ────────────────────────
drop trigger if exists trg_room_members_updated_at on public.room_members;

create trigger trg_room_members_updated_at
  before update on public.room_members
  for each row execute function public.set_updated_at_room_members();
