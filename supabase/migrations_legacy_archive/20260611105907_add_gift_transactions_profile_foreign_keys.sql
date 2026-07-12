do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'gift_transactions_sender_id_fkey'
  ) then
    alter table public.gift_transactions
    add constraint gift_transactions_sender_id_fkey
    foreign key (sender_id)
    references public.profiles(id)
    on delete set null
    not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'gift_transactions_receiver_id_fkey'
  ) then
    alter table public.gift_transactions
    add constraint gift_transactions_receiver_id_fkey
    foreign key (receiver_id)
    references public.profiles(id)
    on delete set null
    not valid;
  end if;
end
$$;

notify pgrst, 'reload schema';
