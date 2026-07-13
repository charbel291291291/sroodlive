-- Wallet transaction compatibility columns.
-- Covers transaction history, coins, diamonds, recharge, gifts, rewards, and admin finance screens.

alter table public.wallet_transactions
add column if not exists label text;

alter table public.wallet_transactions
add column if not exists description text;

alter table public.wallet_transactions
add column if not exists subtitle text;

alter table public.wallet_transactions
add column if not exists transaction_type text;

alter table public.wallet_transactions
add column if not exists type text;

alter table public.wallet_transactions
add column if not exists direction text;

alter table public.wallet_transactions
add column if not exists status text not null default 'completed';

alter table public.wallet_transactions
add column if not exists currency text not null default 'coins';

alter table public.wallet_transactions
add column if not exists coin_amount integer not null default 0;

alter table public.wallet_transactions
add column if not exists diamond_amount integer not null default 0;

alter table public.wallet_transactions
add column if not exists amount integer not null default 0;

alter table public.wallet_transactions
add column if not exists balance_after integer;

alter table public.wallet_transactions
add column if not exists reference_id uuid;

alter table public.wallet_transactions
add column if not exists related_user_id uuid references public.profiles(id) on delete set null;

alter table public.wallet_transactions
add column if not exists room_id uuid references public.rooms(id) on delete set null;

alter table public.wallet_transactions
add column if not exists gift_id uuid references public.gifts(id) on delete set null;

alter table public.wallet_transactions
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.wallet_transactions
add column if not exists created_at timestamptz not null default now();

alter table public.wallet_transactions
add column if not exists updated_at timestamptz not null default now();

update public.wallet_transactions
set label = coalesce(label, transaction_type, type, 'Transaction')
where label is null;

update public.wallet_transactions
set amount = coin_amount
where amount = 0 and coin_amount <> 0;

update public.wallet_transactions
set coin_amount = amount
where coin_amount = 0 and amount <> 0 and currency = 'coins';

update public.wallet_transactions
set diamond_amount = amount
where diamond_amount = 0 and amount <> 0 and currency = 'diamonds';

create index if not exists wallet_transactions_user_id_idx
on public.wallet_transactions (user_id);

create index if not exists wallet_transactions_created_at_idx
on public.wallet_transactions (created_at desc);

create index if not exists wallet_transactions_currency_idx
on public.wallet_transactions (currency);

create index if not exists wallet_transactions_status_idx
on public.wallet_transactions (status);

create index if not exists wallet_transactions_type_idx
on public.wallet_transactions (type);

create index if not exists wallet_transactions_transaction_type_idx
on public.wallet_transactions (transaction_type);