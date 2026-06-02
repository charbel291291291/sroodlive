drop policy if exists "room owners can update room members" on public.room_members;

create policy "room owners can update room members"
on public.room_members
for update
to authenticated
using (
  exists (
    select 1
    from public.rooms
    where rooms.id = room_members.room_id
    and rooms.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.rooms
    where rooms.id = room_members.room_id
    and rooms.owner_id = auth.uid()
  )
);
