-- ────────────────────────────────────────────────────────────────────────────
-- Account deletion (store-compliance / GDPR) + push-token registry.
--
-- Google Play (User Data policy) and Apple (Guideline 5.1.1(v)) both require an
-- in-app way for a user to delete their account and associated personal data.
-- This migration adds the backend for a self-service deletion flow, plus the
-- table the Firebase push foundation needs to register device tokens.
--
-- Deletion model — ANONYMIZE, don't hard-delete:
--   A hard `delete from auth.users` cascades into the wallet/finance ledger
--   (wallet_transactions.user_id references auth.users on delete cascade) and
--   into agency/withdrawal history. For a real-money coin economy we must
--   RETAIN those financial records for accounting/audit/legal obligations,
--   while REMOVING personal data. So request_account_deletion:
--     1. records the request in an auditable table,
--     2. strips PII from the profile (name → 'Deleted User', avatar/bio/phone/
--        email/etc. nulled) and marks it deleted,
--     3. deletes push tokens so the device stops receiving notifications,
--     4. leaves the financial ledger intact (rows now point at an anonymized
--        profile, satisfying "delete personal data" without destroying the
--        money trail).
--   A privileged admin/cron job can later hard-delete the auth row after any
--   legally-required retention window; that is intentionally out of scope here
--   and left to service_role tooling.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. Auditable deletion-request log ───────────────────────────────────────
create table if not exists public.account_deletion_requests (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  status         text not null default 'anonymized'
                   check (status in ('anonymized', 'hard_deleted')),
  reason         text,
  requested_at   timestamptz not null default now(),
  anonymized_at  timestamptz,
  hard_deleted_at timestamptz,
  -- Snapshot of non-PII context for support/audit (never store raw PII here).
  metadata       jsonb not null default '{}'::jsonb
);

create index if not exists account_deletion_requests_user_idx
  on public.account_deletion_requests (user_id, requested_at desc);

alter table public.account_deletion_requests enable row level security;

-- A user may read their own deletion records (e.g. to show "deletion pending").
-- No client INSERT/UPDATE/DELETE: the request is created only by the SECURITY
-- DEFINER RPC below, so the audit row can't be forged or tampered with.
drop policy if exists "adr_select_own" on public.account_deletion_requests;
create policy "adr_select_own"
  on public.account_deletion_requests for select to authenticated
  using (user_id = auth.uid());

revoke all on public.account_deletion_requests from anon, authenticated, public;
grant select on public.account_deletion_requests to authenticated;

comment on table public.account_deletion_requests is
  'Audit trail of in-app account-deletion requests. Writes happen only inside '
  'request_account_deletion (SECURITY DEFINER); clients may read their own rows.';


-- ── 2. Push-token registry (Firebase FCM foundation) ────────────────────────
create table if not exists public.user_push_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token       text not null,
  platform    text not null default 'android'
                check (platform in ('android', 'ios', 'web')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- One row per device token; re-registering the same token just refreshes it.
  constraint user_push_tokens_token_key unique (token)
);

create index if not exists user_push_tokens_user_idx
  on public.user_push_tokens (user_id);

alter table public.user_push_tokens enable row level security;

-- Owner-only read; all writes go through upsert_push_token (SECURITY DEFINER)
-- so a client can't register a token under another user's id.
drop policy if exists "upt_select_own" on public.user_push_tokens;
create policy "upt_select_own"
  on public.user_push_tokens for select to authenticated
  using (user_id = auth.uid());

revoke all on public.user_push_tokens from anon, authenticated, public;
grant select on public.user_push_tokens to authenticated;

comment on table public.user_push_tokens is
  'FCM device tokens for push delivery. Read-own-rows only; writes via '
  'upsert_push_token / delete on account deletion (SECURITY DEFINER).';


-- ── 3. upsert_push_token(token, platform) ───────────────────────────────────
-- Registers/refreshes the caller's device token. If the token already exists
-- (e.g. the device was previously signed in as another user) it is reassigned
-- to the current user and its timestamp refreshed.
create or replace function public.upsert_push_token(
  p_token    text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'invalid_token';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    p_platform := 'android';
  end if;

  insert into public.user_push_tokens (user_id, token, platform)
  values (v_uid, p_token, p_platform)
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.upsert_push_token(text, text) from public, anon;
grant execute on function public.upsert_push_token(text, text) to authenticated;


-- ── 4. request_account_deletion(reason) ─────────────────────────────────────
-- Self-service deletion for the signed-in user. Anonymizes PII, records an
-- audit row, and removes push tokens. Financial/ledger rows are preserved but
-- now reference an anonymized profile. The profile's PII columns are nulled
-- dynamically so this stays correct even though the profiles table was created
-- outside migrations (schema drift): we only touch columns that actually exist.
create or replace function public.request_account_deletion(
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_request   uuid;
  v_col       text;
  -- PII columns to null out if present on public.profiles.
  v_pii_cols  text[] := array[
    'avatar_url', 'bio', 'phone', 'email', 'username',
    'country', 'gender', 'birthdate'
  ];
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Idempotent: if already anonymized, return the existing record instead of
  -- re-processing (protects against double-taps / retries).
  select id into v_request
  from public.account_deletion_requests
  where user_id = v_uid
  order by requested_at desc
  limit 1;

  if v_request is not null then
    return json_build_object('status', 'already_requested', 'request_id', v_request);
  end if;

  -- 1. Audit row first, so there is always a record even if a later step is
  --    rolled back by an error.
  insert into public.account_deletion_requests (user_id, status, reason, anonymized_at)
  values (v_uid, 'anonymized', left(coalesce(p_reason, ''), 500), now())
  returning id into v_request;

  -- 2. Anonymize the display name (the one PII column we know exists and that
  --    every other feature reads). Guarded so a missing column can't abort.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'display_name'
  ) then
    execute 'update public.profiles set display_name = $1 where id = $2'
      using 'Deleted User', v_uid;
  end if;

  -- 3. Mark the profile as deleted if such a flag exists (best-effort; several
  --    possible column names depending on schema history).
  foreach v_col in array array['is_deleted', 'deleted_at', 'status', 'account_status'] loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles'
        and column_name = v_col
    ) then
      if v_col = 'is_deleted' then
        execute 'update public.profiles set is_deleted = true where id = $1' using v_uid;
      elsif v_col = 'deleted_at' then
        execute 'update public.profiles set deleted_at = now() where id = $1' using v_uid;
      else
        -- text status column
        execute format('update public.profiles set %I = $1 where id = $2', v_col)
          using 'deleted', v_uid;
      end if;
    end if;
  end loop;

  -- 4. Null every other PII column that exists.
  foreach v_col in array v_pii_cols loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles'
        and column_name = v_col
    ) then
      execute format('update public.profiles set %I = null where id = $1', v_col)
        using v_uid;
    end if;
  end loop;

  -- 5. Stop notifications to this account's devices.
  delete from public.user_push_tokens where user_id = v_uid;

  return json_build_object(
    'status',     'anonymized',
    'request_id', v_request,
    'server_now', now()
  );
end;
$$;

revoke all on function public.request_account_deletion(text) from public, anon;
grant execute on function public.request_account_deletion(text) to authenticated;

comment on function public.request_account_deletion(text) is
  'Self-service account deletion: anonymizes PII on the caller''s profile, '
  'records an audit row, and removes push tokens. Financial ledger rows are '
  'intentionally preserved (now anonymized) for accounting/legal retention; '
  'hard auth.users deletion is left to privileged service_role tooling.';
