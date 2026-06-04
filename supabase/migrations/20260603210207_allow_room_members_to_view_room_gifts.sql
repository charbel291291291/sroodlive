drop policy if exists "Room members can view room gift transactions" on public.gift_transactions;

create policy "Room members can view room gift transactions"
on public.gift_transactions
for select
to authenticated
using (
  exists (
    select 1
    from public.room_members rm
    where rm.room_id = gift_transactions.room_id
      and rm.user_id = auth.uid()
      and rm.left_at is null
  )
);