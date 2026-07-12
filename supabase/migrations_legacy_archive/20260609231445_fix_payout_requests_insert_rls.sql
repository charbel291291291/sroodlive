-- Fix payout request insert permission for authenticated users

alter table public.payout_requests enable row level security;

drop policy if exists "Users can create their own payout requests" on public.payout_requests;

create policy "Users can create their own payout requests"
on public.payout_requests
for insert
to authenticated
with check (
  user_id = auth.uid()
);
