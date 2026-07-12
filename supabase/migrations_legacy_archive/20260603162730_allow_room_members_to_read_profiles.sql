drop policy if exists "Active room members can read co-member profiles" on public.profiles;

create policy "Active room members can read co-member profiles"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.room_members target_member
    join public.room_members viewer_member
      on viewer_member.room_id = target_member.room_id
    where target_member.user_id = profiles.id
      and target_member.left_at is null
      and viewer_member.user_id = auth.uid()
      and viewer_member.left_at is null
  )
);
