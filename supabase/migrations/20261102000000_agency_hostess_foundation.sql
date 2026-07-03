-- ────────────────────────────────────────────────────────────────────────────
-- Agency / Hostess — Phase 1: security + membership foundation.
--
-- Scope (backend only): harden agency_applications, add secure application +
-- review RPCs, an authoritative effective-dated host↔agency binding
-- (agency_hosts), an agency join-code, and an audit log. No dashboards, no
-- commission changes. Does NOT touch games, IAP, recharge_agencies, or wallet
-- mutation logic. All sensitive actions go through SECURITY DEFINER RPCs.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. Harden agency_applications ───────────────────────────────────────────
-- Add review-audit columns so approvals can be attributed and never forged.
alter table public.agency_applications
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz;

-- The old INSERT policy was `WITH CHECK (true)` + a client INSERT grant, so any
-- authenticated user could forge an application (arbitrary user_id / agency_id /
-- status). Remove that path entirely — applications are created ONLY by the
-- SECURITY DEFINER RPCs below, which force user_id = auth.uid() and
-- status = 'pending'. SELECT (own/admin) and the admin-only UPDATE policy are
-- retained so existing admin reads keep working.
drop policy if exists "Users can create own agency applications" on public.agency_applications;
revoke insert, delete on public.agency_applications from anon, authenticated;
revoke insert, delete on public.agency_applications from public;

comment on table public.agency_applications is
  'Agency/host applications. Client cannot INSERT/DELETE directly; created via '
  'apply_to_* SECURITY DEFINER RPCs (user_id forced to auth.uid(), status forced '
  'to pending). Reviewed via admin_review_agency_application / '
  'agency_owner_review_application.';


-- ── 2. Agency join-code (invite foundation) ─────────────────────────────────
alter table public.agencies
  add column if not exists agency_code text;

create unique index if not exists agencies_agency_code_key
  on public.agencies (agency_code) where agency_code is not null;

-- Internal: generate a unique 6-char code. Not client-callable.
create or replace function public._gen_agency_code()
returns text
language plpgsql
as $$
declare
  v_code text;
begin
  loop
    v_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.agencies where agency_code = v_code);
  end loop;
  return v_code;
end;
$$;
revoke all on function public._gen_agency_code() from public, anon, authenticated;

-- Backfill codes for existing agencies that don't have one.
update public.agencies
set agency_code = public._gen_agency_code()
where agency_code is null;


-- ── 3. agency_hosts: authoritative, effective-dated membership ──────────────
create table if not exists public.agency_hosts (
  id             uuid primary key default gen_random_uuid(),
  agency_id      uuid not null references public.agencies(id) on delete cascade,
  host_user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at      timestamptz not null default now(),
  left_at        timestamptz,
  status         text not null default 'active'
                   check (status in ('active', 'left', 'transferred')),
  approved_by    uuid references auth.users(id),
  application_id uuid references public.agency_applications(id),
  created_at     timestamptz not null default now()
);

-- At most one ACTIVE membership per host (history rows keep left/transferred).
create unique index if not exists agency_hosts_one_active
  on public.agency_hosts (host_user_id) where status = 'active';
create index if not exists agency_hosts_agency_idx
  on public.agency_hosts (agency_id, status);

alter table public.agency_hosts enable row level security;
-- Read: the host themself, the agency owner, or an admin. No client writes.
drop policy if exists "agency_hosts_read" on public.agency_hosts;
create policy "agency_hosts_read"
  on public.agency_hosts for select to authenticated
  using (
    host_user_id = auth.uid()
    or exists (select 1 from public.agencies a
               where a.id = agency_id and a.owner_user_id = auth.uid())
    or public.profile_hub_admin_access()
  );
revoke all on public.agency_hosts from anon, authenticated, public;
grant select on public.agency_hosts to authenticated;

comment on table public.agency_hosts is
  'Authoritative effective-dated host↔agency membership. Read-own / owner / '
  'admin; all writes via SECURITY DEFINER RPCs. Old agency_members is kept in '
  'sync but agency_hosts is the source of truth going forward.';

-- Backfill active memberships from agency_members (non-owners only), one active
-- row per host. Legacy agency_members is preserved untouched.
insert into public.agency_hosts (agency_id, host_user_id, joined_at, status)
select am.agency_id, am.user_id, coalesce(am.joined_at, now()), 'active'
from public.agency_members am
join public.agencies a on a.id = am.agency_id
where am.status = 'active'
  and a.owner_user_id is not null
  and a.owner_user_id <> am.user_id
  and not exists (
    select 1 from public.agency_hosts h
    where h.host_user_id = am.user_id and h.status = 'active'
  );


-- ── 4. Audit log ────────────────────────────────────────────────────────────
create table if not exists public.agency_audit_log (
  id             uuid primary key default gen_random_uuid(),
  actor_user_id  uuid,
  event          text not null,   -- application_submitted / approved / rejected /
                                  -- host_assigned / host_removed / host_transferred
  agency_id      uuid,
  host_user_id   uuid,
  application_id uuid,
  detail         jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists agency_audit_log_agency_idx
  on public.agency_audit_log (agency_id, created_at desc);

alter table public.agency_audit_log enable row level security;
drop policy if exists "agency_audit_read" on public.agency_audit_log;
create policy "agency_audit_read"
  on public.agency_audit_log for select to authenticated
  using (
    public.profile_hub_admin_access()
    or exists (select 1 from public.agencies a
               where a.id = agency_id and a.owner_user_id = auth.uid())
  );
revoke all on public.agency_audit_log from anon, authenticated, public;
grant select on public.agency_audit_log to authenticated;

-- Internal audit writer (not client-callable).
create or replace function public._agency_audit(
  p_actor uuid, p_event text, p_agency uuid, p_host uuid, p_app uuid, p_detail jsonb
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.agency_audit_log
    (actor_user_id, event, agency_id, host_user_id, application_id, detail)
  values (p_actor, p_event, p_agency, p_host, p_app, coalesce(p_detail, '{}'::jsonb));
$$;
revoke all on function public._agency_audit(uuid, text, uuid, uuid, uuid, jsonb)
  from public, anon, authenticated;


-- ── 5. Internal: grant membership from an approved application ──────────────
-- agency_id is read from the (server-created) application row — never trusted
-- from the client at review time. Handles transfer (closes prior active row).
create or replace function public._agency_grant_membership(
  p_application_id uuid, p_approver uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.agency_applications;
begin
  select * into v_app from public.agency_applications where id = p_application_id;
  if v_app.id is null then raise exception 'application_not_found'; end if;

  -- become_host / create_agency carry no agency to bind.
  if v_app.agency_id is null then
    return;
  end if;

  -- Transfer: close any existing active membership at a different agency.
  update public.agency_hosts
  set status = 'transferred', left_at = now()
  where host_user_id = v_app.user_id
    and status = 'active'
    and agency_id <> v_app.agency_id;

  -- Create the new active membership if the host isn't already active here.
  if not exists (
    select 1 from public.agency_hosts
    where host_user_id = v_app.user_id and status = 'active'
      and agency_id = v_app.agency_id
  ) then
    insert into public.agency_hosts
      (agency_id, host_user_id, status, approved_by, application_id)
    values (v_app.agency_id, v_app.user_id, 'active', p_approver, v_app.id);
  end if;

  -- Keep legacy agency_members in sync (best-effort; no unique assumption).
  if not exists (
    select 1 from public.agency_members
    where agency_id = v_app.agency_id and user_id = v_app.user_id
  ) then
    insert into public.agency_members (agency_id, user_id, role, status, joined_at)
    values (v_app.agency_id, v_app.user_id, 'host', 'active', now());
  else
    update public.agency_members
    set status = 'active', updated_at = now()
    where agency_id = v_app.agency_id and user_id = v_app.user_id;
  end if;

  perform public._agency_audit(
    p_approver, 'host_assigned', v_app.agency_id, v_app.user_id, v_app.id, '{}'::jsonb);
end;
$$;
revoke all on function public._agency_grant_membership(uuid, uuid)
  from public, anon, authenticated;


-- ── 6. Client-callable application RPCs ─────────────────────────────────────

create or replace function public.apply_to_become_host(
  p_message text default null, p_phone text default null,
  p_country text default null, p_experience text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.agency_applications
             where user_id = v_uid and application_type = 'become_host'
               and status = 'pending') then
    raise exception 'duplicate_pending_application';
  end if;
  insert into public.agency_applications
    (user_id, application_type, status, message, phone, country, experience)
  values (v_uid, 'become_host', 'pending', p_message, p_phone, p_country, p_experience)
  returning id into v_id;
  perform public._agency_audit(v_uid, 'application_submitted', null, v_uid, v_id,
    jsonb_build_object('type', 'become_host'));
  return v_id;
end;
$$;

create or replace function public.apply_to_create_agency(
  p_message text default null, p_phone text default null,
  p_country text default null, p_experience text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from public.agency_applications
             where user_id = v_uid and application_type = 'create_agency'
               and status = 'pending') then
    raise exception 'duplicate_pending_application';
  end if;
  insert into public.agency_applications
    (user_id, application_type, status, message, phone, country, experience)
  values (v_uid, 'create_agency', 'pending', p_message, p_phone, p_country, p_experience)
  returning id into v_id;
  perform public._agency_audit(v_uid, 'application_submitted', null, v_uid, v_id,
    jsonb_build_object('type', 'create_agency'));
  return v_id;
end;
$$;

create or replace function public.apply_to_join_agency(
  p_agency_code text, p_message text default null, p_phone text default null,
  p_country text default null, p_experience text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_agency public.agencies; v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_agency_code is null or length(trim(p_agency_code)) = 0 then
    raise exception 'agency_code_required';
  end if;
  -- Resolve + validate the agency server-side; agency_id is never trusted
  -- from the client.
  select * into v_agency from public.agencies
  where agency_code = upper(trim(p_agency_code)) and status = 'active';
  if v_agency.id is null then raise exception 'invalid_or_inactive_agency'; end if;
  if v_agency.owner_user_id = v_uid then raise exception 'cannot_join_own_agency'; end if;
  if exists (select 1 from public.agency_applications
             where user_id = v_uid and application_type = 'join_agency'
               and status = 'pending') then
    raise exception 'duplicate_pending_application';
  end if;
  insert into public.agency_applications
    (user_id, agency_id, application_type, status, message, phone, country, experience)
  values (v_uid, v_agency.id, 'join_agency', 'pending', p_message, p_phone, p_country, p_experience)
  returning id into v_id;
  perform public._agency_audit(v_uid, 'application_submitted', v_agency.id, v_uid, v_id,
    jsonb_build_object('type', 'join_agency', 'code', v_agency.agency_code));
  return v_id;
end;
$$;

revoke all on function public.apply_to_become_host(text, text, text, text) from public, anon;
grant execute on function public.apply_to_become_host(text, text, text, text) to authenticated;
revoke all on function public.apply_to_create_agency(text, text, text, text) from public, anon;
grant execute on function public.apply_to_create_agency(text, text, text, text) to authenticated;
revoke all on function public.apply_to_join_agency(text, text, text, text, text) from public, anon;
grant execute on function public.apply_to_join_agency(text, text, text, text, text) to authenticated;


-- ── 7. Review RPCs ──────────────────────────────────────────────────────────

create or replace function public.admin_review_agency_application(
  p_application_id uuid, p_approve boolean, p_reply text default null
) returns boolean
language plpgsql security definer set search_path = public
as $$
declare v_admin uuid := auth.uid(); v_app public.agency_applications;
begin
  if v_admin is null or not public.profile_hub_admin_access() then
    raise exception 'not_authorized';
  end if;
  select * into v_app from public.agency_applications where id = p_application_id for update;
  if v_app.id is null then raise exception 'application_not_found'; end if;
  if v_app.status <> 'pending' then raise exception 'application_not_pending'; end if;

  if p_approve then
    update public.agency_applications
    set status = 'approved', admin_reply = p_reply,
        reviewed_by = v_admin, reviewed_at = now(), updated_at = now()
    where id = v_app.id;
    perform public._agency_grant_membership(v_app.id, v_admin);
    perform public._agency_audit(v_admin, 'application_approved',
      v_app.agency_id, v_app.user_id, v_app.id, '{}'::jsonb);
  else
    update public.agency_applications
    set status = 'rejected', admin_reply = p_reply,
        reviewed_by = v_admin, reviewed_at = now(), updated_at = now()
    where id = v_app.id;
    perform public._agency_audit(v_admin, 'application_rejected',
      v_app.agency_id, v_app.user_id, v_app.id, '{}'::jsonb);
  end if;
  return true;
end;
$$;

-- Owner review: only for join_agency applications targeting an agency the
-- caller owns. Ownership is verified server-side against agencies.owner_user_id.
create or replace function public.agency_owner_review_application(
  p_application_id uuid, p_approve boolean, p_reply text default null
) returns boolean
language plpgsql security definer set search_path = public
as $$
declare v_owner uuid := auth.uid(); v_app public.agency_applications; v_agency public.agencies;
begin
  if v_owner is null then raise exception 'not_authenticated'; end if;
  select * into v_app from public.agency_applications where id = p_application_id for update;
  if v_app.id is null then raise exception 'application_not_found'; end if;
  if v_app.application_type <> 'join_agency' or v_app.agency_id is null then
    raise exception 'not_owner_reviewable';
  end if;
  select * into v_agency from public.agencies where id = v_app.agency_id;
  if v_agency.id is null or v_agency.owner_user_id is distinct from v_owner then
    raise exception 'not_agency_owner';
  end if;
  if v_app.status <> 'pending' then raise exception 'application_not_pending'; end if;

  if p_approve then
    update public.agency_applications
    set status = 'approved', admin_reply = p_reply,
        reviewed_by = v_owner, reviewed_at = now(), updated_at = now()
    where id = v_app.id;
    perform public._agency_grant_membership(v_app.id, v_owner);
    perform public._agency_audit(v_owner, 'application_approved',
      v_app.agency_id, v_app.user_id, v_app.id, jsonb_build_object('by', 'owner'));
  else
    update public.agency_applications
    set status = 'rejected', admin_reply = p_reply,
        reviewed_by = v_owner, reviewed_at = now(), updated_at = now()
    where id = v_app.id;
    perform public._agency_audit(v_owner, 'application_rejected',
      v_app.agency_id, v_app.user_id, v_app.id, jsonb_build_object('by', 'owner'));
  end if;
  return true;
end;
$$;

revoke all on function public.admin_review_agency_application(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_agency_application(uuid, boolean, text) to authenticated;
revoke all on function public.agency_owner_review_application(uuid, boolean, text) from public, anon;
grant execute on function public.agency_owner_review_application(uuid, boolean, text) to authenticated;
