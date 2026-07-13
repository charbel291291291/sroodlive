-- Allow users to read profiles of their private message conversation partners.
-- Without this, the room-members-only SELECT policy blocks profile reads in the
-- messages context, causing "Unknown user" in private chat headers.
drop policy if exists "Private message participants can read each other profiles"
  on public.profiles;

create policy "Private message participants can read each other profiles"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1 from public.private_conversations
    where (user_one_id = auth.uid() or user_two_id = auth.uid())
      and (user_one_id = profiles.id or user_two_id = profiles.id)
  )
);
