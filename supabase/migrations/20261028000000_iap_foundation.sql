-- ────────────────────────────────────────────────────────────────────────────
-- In-App Purchase (IAP) foundation — Google Play Billing / Apple StoreKit for
-- COIN purchases only. Foundation layer: catalog + receipt ledger + audit
-- events + a server-side verification RPC stub. No coins are credited yet by a
-- real store flow; this only lays the trustworthy plumbing.
--
-- Security model (why each choice):
--   * Coins are NEVER credited from the client. The client can only submit a
--     purchase receipt/token; a store row is worthless until the server
--     verifies it with Google/Apple. So the client-facing RPC only RECORDS a
--     pending receipt — it never touches wallets.
--   * All wallet mutation stays inside SECURITY DEFINER RPCs. Crediting happens
--     in fulfil_iap_purchase(), which is callable only by the verification
--     backend (service_role / Edge Function), not by anon/authenticated.
--   * Receipts are unique per (platform, purchase_token) so the same store
--     purchase can never be credited twice (idempotency / no double-grant).
--   * Product price/coin amounts live server-side in iap_products, never
--     trusted from the client — the client can't inflate how many coins a
--     product grants.
-- ────────────────────────────────────────────────────────────────────────────


-- ── 1. Product catalog (server-owned source of truth) ───────────────────────
-- The store product_id maps to a fixed coin amount and price here. The client
-- never tells the server how many coins to grant; the server looks it up.
create table if not exists public.iap_products (
  product_id     text primary key,          -- store SKU, e.g. 'coins_100k'
  coins          bigint not null check (coins > 0),
  price_usd_cents integer,                   -- reference price for reporting
  is_active      boolean not null default true,
  sort_order     integer not null default 0,
  created_at     timestamptz not null default now()
);

alter table public.iap_products enable row level security;
-- Read-only catalog for signed-in users (to render the store); no client writes.
drop policy if exists "iap_products_read" on public.iap_products;
create policy "iap_products_read"
  on public.iap_products for select to authenticated
  using (is_active);
revoke all on public.iap_products from anon, authenticated, public;
grant select on public.iap_products to authenticated;

comment on table public.iap_products is
  'Server-owned IAP catalog. product_id -> coins mapping is authoritative; the '
  'client never supplies the coin amount. Read-only to authenticated.';

-- Seed the four coin SKUs required by the client. Prices are placeholders and
-- should mirror the store console configuration.
insert into public.iap_products (product_id, coins, price_usd_cents, sort_order) values
  ('coins_100k',   100000,   199, 1),
  ('coins_500k',   500000,   899, 2),
  ('coins_1m',    1000000,  1699, 3),
  ('coins_5m',    5000000,  7999, 4)
on conflict (product_id) do nothing;


-- ── 2. Purchase receipts (the money ledger) ─────────────────────────────────
-- One row per store purchase. Created 'pending' when the client submits the
-- token; flipped to 'verified' + credited only by the server after Google/
-- Apple confirm it. Unique (platform, purchase_token) => no double-credit.
create table if not exists public.iap_purchase_receipts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  product_id     text not null references public.iap_products(product_id),
  platform       text not null check (platform in ('android', 'ios')),
  purchase_token text not null,             -- Play purchaseToken / Apple txn id
  status         text not null default 'pending'
                   check (status in ('pending','verified','failed','refunded')),
  coins_granted  bigint not null default 0,
  amount_usd_cents integer,
  created_at     timestamptz not null default now(),
  verified_at    timestamptz,
  constraint iap_receipts_token_unique unique (platform, purchase_token)
);

create index if not exists iap_receipts_user_idx
  on public.iap_purchase_receipts (user_id, created_at desc);
create index if not exists iap_receipts_status_idx
  on public.iap_purchase_receipts (status);

alter table public.iap_purchase_receipts enable row level security;
-- Users may read their own receipts (order history). No client writes at all —
-- receipts are created by record_iap_purchase() and finalized by the server.
drop policy if exists "iap_receipts_select_own" on public.iap_purchase_receipts;
create policy "iap_receipts_select_own"
  on public.iap_purchase_receipts for select to authenticated
  using (user_id = auth.uid());
revoke all on public.iap_purchase_receipts from anon, authenticated, public;
grant select on public.iap_purchase_receipts to authenticated;

comment on table public.iap_purchase_receipts is
  'IAP receipt ledger. Read-own-rows only; all writes via SECURITY DEFINER RPCs. '
  'Unique (platform, purchase_token) prevents double-crediting the same store '
  'purchase.';


-- ── 3. Purchase events (immutable audit trail) ──────────────────────────────
create table if not exists public.iap_purchase_events (
  id          uuid primary key default gen_random_uuid(),
  receipt_id  uuid references public.iap_purchase_receipts(id) on delete set null,
  user_id     uuid references auth.users(id) on delete set null,
  event       text not null,                -- 'submitted','verified','failed','refunded'
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists iap_events_receipt_idx
  on public.iap_purchase_events (receipt_id, created_at desc);

alter table public.iap_purchase_events enable row level security;
-- Audit log: no client access at all (default-deny, all grants revoked).
revoke all on public.iap_purchase_events from anon, authenticated, public;

comment on table public.iap_purchase_events is
  'Immutable IAP audit trail. No client access; written only by SECURITY '
  'DEFINER RPCs / the verification backend.';


-- ── 4. record_iap_purchase(product_id, platform, purchase_token) ────────────
-- Client-callable. Records a PENDING receipt for a store purchase the client
-- just completed. Deliberately does NOT touch wallets or grant coins — the
-- token is unverified. Idempotent: resubmitting the same token returns the
-- existing receipt instead of creating a duplicate.
create or replace function public.record_iap_purchase(
  p_product_id     text,
  p_platform       text,
  p_purchase_token text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_product public.iap_products;
  v_receipt public.iap_purchase_receipts;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_platform not in ('android','ios') then raise exception 'invalid_platform'; end if;
  if p_purchase_token is null or length(trim(p_purchase_token)) = 0 then
    raise exception 'invalid_token';
  end if;

  select * into v_product from public.iap_products
  where product_id = p_product_id and is_active;
  if v_product.product_id is null then raise exception 'unknown_product'; end if;

  -- Idempotent on (platform, purchase_token): return existing receipt if any.
  select * into v_receipt from public.iap_purchase_receipts
  where platform = p_platform and purchase_token = p_purchase_token;

  if v_receipt.id is null then
    insert into public.iap_purchase_receipts
      (user_id, product_id, platform, purchase_token, status, amount_usd_cents)
    values
      (v_uid, p_product_id, p_platform, p_purchase_token, 'pending', v_product.price_usd_cents)
    returning * into v_receipt;

    insert into public.iap_purchase_events (receipt_id, user_id, event, detail)
    values (v_receipt.id, v_uid, 'submitted',
            jsonb_build_object('product_id', p_product_id, 'platform', p_platform));
  end if;

  return json_build_object(
    'receipt_id', v_receipt.id,
    'status',     v_receipt.status,
    'product_id', v_receipt.product_id
  );
end;
$$;

revoke all on function public.record_iap_purchase(text, text, text) from public, anon;
grant execute on function public.record_iap_purchase(text, text, text) to authenticated;

comment on function public.record_iap_purchase(text, text, text) is
  'Records a PENDING IAP receipt for a client-completed store purchase. Never '
  'credits coins (token is unverified). Idempotent on (platform, purchase_token).';


-- ── 5. fulfil_iap_purchase(receipt_id, verified, coins) — SERVER ONLY ───────
-- Called by the verification backend (Edge Function / service_role) AFTER it
-- confirms the receipt with Google Play / Apple. This is the ONLY path that
-- credits coins. It is NOT granted to anon/authenticated, so a client can never
-- self-fulfil. Idempotent: a receipt already 'verified' is not re-credited.
--
-- NOTE: this is the foundation stub. The real Google/Apple API verification is
-- performed by the Edge Function BEFORE calling this; here we only trust the
-- caller because table-level EXECUTE is restricted to privileged roles.
create or replace function public.fulfil_iap_purchase(
  p_receipt_id uuid,
  p_verified   boolean,
  p_coins      bigint default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt public.iap_purchase_receipts;
  v_product public.iap_products;
  v_coins   bigint;
  v_new_bal integer;
begin
  select * into v_receipt from public.iap_purchase_receipts
  where id = p_receipt_id for update;
  if v_receipt.id is null then raise exception 'receipt_not_found'; end if;

  -- Idempotent: never credit a receipt twice.
  if v_receipt.status = 'verified' then
    return json_build_object('status', 'verified', 'already', true,
                             'coins_granted', v_receipt.coins_granted);
  end if;

  if not p_verified then
    update public.iap_purchase_receipts
    set status = 'failed', verified_at = now()
    where id = v_receipt.id;
    insert into public.iap_purchase_events (receipt_id, user_id, event)
    values (v_receipt.id, v_receipt.user_id, 'failed');
    return json_build_object('status', 'failed');
  end if;

  -- Coin amount comes from the server catalog, never the client.
  select * into v_product from public.iap_products where product_id = v_receipt.product_id;
  v_coins := coalesce(p_coins, v_product.coins);

  update public.wallets
  set coins_balance = coins_balance + v_coins, updated_at = now()
  where user_id = v_receipt.user_id
  returning coins_balance into v_new_bal;

  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, balance_coins_after, note, metadata)
  values
    (v_receipt.user_id, 'recharge_request', 'credit', v_coins, 0, v_new_bal,
     'IAP coin purchase',
     jsonb_build_object('receipt_id', v_receipt.id, 'product_id', v_receipt.product_id,
                        'platform', v_receipt.platform, 'source', 'iap'));

  update public.iap_purchase_receipts
  set status = 'verified', coins_granted = v_coins, verified_at = now()
  where id = v_receipt.id;

  insert into public.iap_purchase_events (receipt_id, user_id, event, detail)
  values (v_receipt.id, v_receipt.user_id, 'verified',
          jsonb_build_object('coins', v_coins));

  return json_build_object('status', 'verified', 'coins_granted', v_coins,
                           'new_balance', v_new_bal);
end;
$$;

-- SERVER ONLY: not granted to anon/authenticated. Only service_role (used by
-- the Edge Function after real Google/Apple verification) may execute this.
revoke all on function public.fulfil_iap_purchase(uuid, boolean, bigint)
  from public, anon, authenticated;

comment on function public.fulfil_iap_purchase(uuid, boolean, bigint) is
  'SERVER-ONLY coin fulfilment. The single path that credits IAP coins, callable '
  'only by service_role / the verification Edge Function after confirming the '
  'receipt with the store. Idempotent; coin amount taken from the server catalog.';
