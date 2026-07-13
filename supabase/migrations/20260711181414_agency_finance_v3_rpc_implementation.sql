-- Agency Finance V3 RPC implementation (isolated staging surface).
--
-- Review corrections applied before any deployment (this migration has never
-- been applied to any environment):
--   1. Request lifecycle: recharge/withdrawal REQUESTS are created 'pending'
--      and transition pending -> completed (approval) or pending -> rejected.
--      Approving/rejecting a non-pending request fails, which also prevents
--      duplicate approvals under concurrency (source row is locked FOR UPDATE).
--   2. Ledger movement happens exactly once per flow and in the correct
--      direction: recharge_posting / agency_commission / agency_settlement /
--      administrative_correction move clearing -> wallet; withdrawal_approval
--      moves wallet -> clearing. Requests, approvals-of-recharges, and
--      rejections post NO ledger entries.
--   3. Reversals copy the real amounts/currency/parties from the reversed
--      operation, post entries in the OPPOSITE direction, and mark the source
--      status='reversed' with reversed_at. Only completed movement operations
--      are reversible; a reversed source cannot be reversed again.
--   4. Wrapper RPCs no longer inject fake placeholder amounts; amounts are
--      derived from the source operation (approval/rejection/posting/reversal)
--      or validated from the caller payload (create/commission/settlement).
--   5. Self-approval: the request creator or its agent may not approve or post
--      their own recharge, nor approve their own withdrawal.
--   6. The ledger currency tag is derived from the same dimension as the
--      headline amount (fiat -> caller-supplied fiat currency required;
--      coins -> 'COIN'; diamonds -> 'DIAMOND').
--   7. No grants to authenticated: the V3 surface stays fail-closed and
--      isolated, matching the Phase 3 posture. Staging must grant explicitly.
--      NOTE: auth.uid() is NULL for pure service_role calls, so staging tests
--      must execute with an impersonated user JWT (or a dedicated staging role
--      granted execute) — not the bare service key.

create or replace function agency_finance_v3._is_finance_admin()
returns boolean language sql stable security definer
set search_path = pg_catalog, public, agency_finance_v3
as $$ select auth.uid() is not null and public.has_finance_access() $$;

create or replace function agency_finance_v3._execute_operation(
  p_scope text, p_key text, p_type text, p_payload jsonb,
  p_requires_finance_admin boolean default false
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, agency_finance_v3
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text := p_payload::text;
  v_claim agency_finance_v3.agency_idempotency_keys%rowtype;
  v_source agency_finance_v3.agency_financial_operations%rowtype;
  v_operation uuid;
  v_result jsonb;
  v_beneficiary uuid := nullif(p_payload->>'beneficiary_user_id','')::uuid;
  v_agency uuid := nullif(p_payload->>'agency_id','')::uuid;
  v_agent uuid := nullif(p_payload->>'agent_id','')::uuid;
  v_request uuid := nullif(p_payload->>'request_id','')::uuid;
  v_transaction uuid := nullif(p_payload->>'transaction_id','')::uuid;
  v_reversal uuid := nullif(p_payload->>'reversal_of','')::uuid;
  v_currency text := upper(coalesce(nullif(p_payload->>'currency',''),''));
  v_coins bigint := coalesce((p_payload->>'coin_amount')::bigint,0);
  v_diamonds bigint := coalesce((p_payload->>'diamond_amount')::bigint,0);
  v_fiat numeric := coalesce((p_payload->>'fiat_amount')::numeric,0);
  v_rate numeric := coalesce((p_payload->>'exchange_rate')::numeric,1);
  v_amount numeric;
  v_clearing uuid;
  v_wallet uuid;
  v_debit uuid;
  v_credit uuid;
  v_now timestamptz := clock_timestamp();
  v_status text;
  v_completed timestamptz;
  v_posts boolean;
  v_wallet_to_clearing boolean;
begin
  if v_actor is null then raise exception 'not_authenticated'; end if;
  if p_requires_finance_admin and not agency_finance_v3._is_finance_admin() then
    raise exception 'not_authorized';
  end if;
  if nullif(btrim(p_key),'') is null then raise exception 'idempotency_key_required'; end if;

  -- Idempotency claim: insert-or-wait, then re-read under lock. A failed
  -- attempt rolls the claim back with the transaction, so retries are safe;
  -- a completed claim short-circuits with the cached result.
  insert into agency_finance_v3.agency_idempotency_keys
    (operation_scope,idempotency_key,actor_user_id,request_hash)
  values (p_scope,p_key,v_actor,v_hash)
  on conflict (operation_scope,idempotency_key) do nothing;

  select * into v_claim from agency_finance_v3.agency_idempotency_keys
  where operation_scope=p_scope and idempotency_key=p_key for update;
  if v_claim.actor_user_id <> v_actor or v_claim.request_hash <> v_hash then
    raise exception 'idempotency_conflict';
  end if;
  if v_claim.status='completed' then return v_claim.result; end if;

  -- ── Source resolution + lifecycle validation ─────────────────────────────
  if p_type in ('recharge_approval','recharge_rejection','recharge_posting',
                'withdrawal_approval','withdrawal_rejection') then
    if v_request is null then raise exception 'request_id_required'; end if;

    select * into v_source
    from agency_finance_v3.agency_financial_operations
    where operation_id = v_request
    for update;
    if not found then raise exception 'source_request_not_found'; end if;

    if p_type like 'recharge%' and v_source.operation_type <> 'recharge_request' then
      raise exception 'invalid_source_request_type';
    end if;
    if p_type like 'withdrawal%' and v_source.operation_type <> 'withdrawal_request' then
      raise exception 'invalid_source_request_type';
    end if;

    -- Real amounts always come from the source request, never the payload.
    v_beneficiary := v_source.beneficiary_user_id;
    v_agency      := v_source.agency_id;
    v_agent       := v_source.agent_id;
    v_currency    := v_source.currency;
    v_coins       := v_source.coin_amount;
    v_diamonds    := v_source.diamond_amount;
    v_fiat        := v_source.fiat_amount;
    v_rate        := v_source.exchange_rate;

    if p_type in ('recharge_approval','recharge_rejection',
                  'withdrawal_approval','withdrawal_rejection') then
      if v_source.status <> 'pending' then
        raise exception 'request_not_pending';
      end if;
    elsif p_type = 'recharge_posting' then
      if v_source.status <> 'completed' then
        raise exception 'request_not_approved';
      end if;
      if exists (
        select 1 from agency_finance_v3.agency_financial_operations
        where request_id = v_request
          and operation_type = 'recharge_posting'
          and status = 'completed'
      ) then
        raise exception 'request_already_posted';
      end if;
    end if;

    -- Neither the request creator nor its agent may approve/post it.
    if p_type in ('recharge_approval','recharge_posting','withdrawal_approval')
       and (v_actor = v_source.actor_user_id or v_actor = v_agent) then
      raise exception 'self_approval_forbidden';
    end if;

  elsif p_type = 'reversal' then
    if v_reversal is null then raise exception 'reversal_of_required'; end if;

    select * into v_source
    from agency_finance_v3.agency_financial_operations
    where operation_id = v_reversal
    for update;
    if not found or v_source.status <> 'completed' then
      raise exception 'reversal_source_not_completed';
    end if;
    if v_source.operation_type not in
       ('recharge_posting','withdrawal_approval','agency_commission',
        'agency_settlement','administrative_correction') then
      raise exception 'source_operation_not_reversible';
    end if;

    v_beneficiary := v_source.beneficiary_user_id;
    v_agency      := v_source.agency_id;
    v_agent       := v_source.agent_id;
    v_currency    := v_source.currency;
    v_coins       := v_source.coin_amount;
    v_diamonds    := v_source.diamond_amount;
    v_fiat        := v_source.fiat_amount;
    v_rate        := v_source.exchange_rate;

  else
    -- Caller-supplied amounts: create_* requests, commission, settlement.
    if v_coins < 0 or v_diamonds < 0 or v_fiat < 0
       or (v_coins = 0 and v_diamonds = 0 and v_fiat = 0) then
      raise exception 'positive_amount_required';
    end if;
    -- Currency tag must match the dimension the headline amount comes from.
    if v_fiat > 0 then
      if v_currency = '' or v_currency in ('COIN','DIAMOND') then
        raise exception 'fiat_currency_required';
      end if;
    elsif v_coins > 0 then
      v_currency := 'COIN';
    else
      v_currency := 'DIAMOND';
    end if;
  end if;

  if v_rate is null or v_rate <= 0 then
    raise exception 'exchange_rate_must_be_positive';
  end if;

  v_amount := case when v_fiat > 0 then v_fiat
                   when v_coins > 0 then v_coins
                   else v_diamonds end;

  -- ── Operation row ─────────────────────────────────────────────────────────
  v_status := case when p_type in ('recharge_request','withdrawal_request')
                   then 'pending' else 'completed' end;
  v_completed := case when v_status = 'completed' then v_now else null end;

  insert into agency_finance_v3.agency_financial_operations (
    idempotency_key,request_id,transaction_id,actor_user_id,
    beneficiary_user_id,agency_id,agent_id,currency,coin_amount,
    diamond_amount,fiat_amount,exchange_rate,operation_type,status,
    completed_at,reversal_of,metadata
  ) values (
    p_key,v_request,v_transaction,v_actor,coalesce(v_beneficiary,v_actor),
    v_agency,v_agent,v_currency,v_coins,v_diamonds,v_fiat,v_rate,p_type,
    v_status,v_completed,v_reversal,p_payload
  ) returning operation_id into v_operation;

  -- ── Ledger entries: only real movements, correct direction ───────────────
  v_posts := p_type in ('recharge_posting','withdrawal_approval',
                        'agency_commission','agency_settlement',
                        'administrative_correction','reversal');
  if v_posts then
    if p_type = 'reversal' then
      -- Opposite direction of the reversed movement.
      v_wallet_to_clearing := (v_source.operation_type <> 'withdrawal_approval');
    else
      v_wallet_to_clearing := (p_type = 'withdrawal_approval');
    end if;

    insert into agency_finance_v3.agency_ledger_accounts
      (owner_type,owner_id,currency,account_code)
    values ('clearing','00000000-0000-0000-0000-000000000000',v_currency,'V3_CLEARING')
    on conflict (owner_type,owner_id,currency,account_code) do nothing
    returning account_id into v_clearing;
    if v_clearing is null then
      select account_id into v_clearing
      from agency_finance_v3.agency_ledger_accounts
      where owner_type='clearing'
        and owner_id='00000000-0000-0000-0000-000000000000'
        and currency=v_currency and account_code='V3_CLEARING';
    end if;

    insert into agency_finance_v3.agency_ledger_accounts
      (owner_type,owner_id,currency,account_code)
    values ('wallet',coalesce(v_beneficiary,v_actor),v_currency,'V3_WALLET')
    on conflict (owner_type,owner_id,currency,account_code) do nothing
    returning account_id into v_wallet;
    if v_wallet is null then
      select account_id into v_wallet
      from agency_finance_v3.agency_ledger_accounts
      where owner_type='wallet' and owner_id=coalesce(v_beneficiary,v_actor)
        and currency=v_currency and account_code='V3_WALLET';
    end if;

    if v_wallet_to_clearing then
      v_debit := v_wallet; v_credit := v_clearing;
    else
      v_debit := v_clearing; v_credit := v_wallet;
    end if;

    insert into agency_finance_v3.agency_ledger_entries
      (operation_id,account_id,request_id,transaction_id,entry_side,currency,
       amount,coin_amount,diamond_amount,fiat_amount,created_by)
    values
      (v_operation,v_debit,v_request,v_transaction,'debit',v_currency,v_amount,
       v_coins,v_diamonds,v_fiat,v_actor),
      (v_operation,v_credit,v_request,v_transaction,'credit',v_currency,v_amount,
       v_coins,v_diamonds,v_fiat,v_actor);
  end if;

  -- ── Source lifecycle transition ──────────────────────────────────────────
  if p_type in ('recharge_approval','withdrawal_approval') then
    update agency_finance_v3.agency_financial_operations
    set status='completed', completed_at=v_now
    where operation_id=v_request;
  elsif p_type in ('recharge_rejection','withdrawal_rejection') then
    update agency_finance_v3.agency_financial_operations
    set status='rejected'
    where operation_id=v_request;
  elsif p_type = 'reversal' then
    update agency_finance_v3.agency_financial_operations
    set status='reversed', reversed_at=v_now
    where operation_id=v_reversal;
  end if;

  insert into agency_finance_v3.agency_audit_events
    (operation_id,actor_user_id,event_type,agency_id,target_user_id,
     correlation_id,metadata)
  select operation_id,v_actor,p_type,v_agency,coalesce(v_beneficiary,v_actor),
    correlation_id,p_payload
  from agency_finance_v3.agency_financial_operations where operation_id=v_operation;

  v_result := jsonb_build_object('operation_id',v_operation,'status',v_status);
  update agency_finance_v3.agency_idempotency_keys
  set operation_id=v_operation,status='completed',result=v_result,
      completed_at=clock_timestamp()
  where idempotency_id=v_claim.idempotency_id;
  return v_result;
end $$;

-- Wrappers: no placeholder amounts; source-derived operations pass only ids.
create or replace function agency_finance_v3.create_recharge_request(p_idempotency_key text,p_payload jsonb)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('create_recharge_request',$1,'recharge_request',$2,false) $$;
create or replace function agency_finance_v3.approve_recharge_request(p_idempotency_key text,p_request_id uuid)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('approve_recharge_request',$1,'recharge_approval',jsonb_build_object('request_id',$2),true) $$;
create or replace function agency_finance_v3.reject_recharge_request(p_idempotency_key text,p_request_id uuid,p_reason text)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('reject_recharge_request',$1,'recharge_rejection',jsonb_build_object('request_id',$2,'reason',$3),true) $$;
create or replace function agency_finance_v3.post_recharge_transaction(p_idempotency_key text,p_request_id uuid)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('post_recharge_transaction',$1,'recharge_posting',jsonb_build_object('request_id',$2),true) $$;
create or replace function agency_finance_v3.create_withdrawal_request(p_idempotency_key text,p_payload jsonb)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('create_withdrawal_request',$1,'withdrawal_request',$2,false) $$;
create or replace function agency_finance_v3.approve_withdrawal_request(p_idempotency_key text,p_request_id uuid)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('approve_withdrawal_request',$1,'withdrawal_approval',jsonb_build_object('request_id',$2),true) $$;
create or replace function agency_finance_v3.reject_withdrawal_request(p_idempotency_key text,p_request_id uuid,p_reason text)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('reject_withdrawal_request',$1,'withdrawal_rejection',jsonb_build_object('request_id',$2,'reason',$3),true) $$;
create or replace function agency_finance_v3.reverse_financial_operation(p_idempotency_key text,p_operation_id uuid,p_reason text)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('reverse_financial_operation',$1,'reversal',jsonb_build_object('reversal_of',$2,'reason',$3),true) $$;
create or replace function agency_finance_v3.post_agency_commission(p_idempotency_key text,p_payload jsonb)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('post_agency_commission',$1,'agency_commission',$2,true) $$;
create or replace function agency_finance_v3.post_agency_settlement(p_idempotency_key text,p_payload jsonb)
returns jsonb language sql security definer set search_path=pg_catalog,public,agency_finance_v3
as $$ select agency_finance_v3._execute_operation('post_agency_settlement',$1,'agency_settlement',$2,true) $$;

-- Fail-closed: the V3 surface stays isolated. NO grants to authenticated —
-- staging enables access explicitly (impersonated user JWT or dedicated role).
revoke execute on all functions in schema agency_finance_v3 from public, anon, authenticated;
grant execute on all functions in schema agency_finance_v3 to service_role;
