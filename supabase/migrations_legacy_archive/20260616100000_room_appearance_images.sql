-- Add room_avatar_url to rooms (cover_url already exists)
alter table public.rooms
  add column if not exists room_avatar_url text;

-- Storage buckets for room images (created via SQL for migration reproducibility)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('room_covers',  'room_covers',  true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('room_avatars', 'room_avatars', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- RLS: anyone can read room images
drop policy if exists "room_covers_select" on storage.objects;
create policy "room_covers_select" on storage.objects for select using (bucket_id = 'room_covers');

drop policy if exists "room_avatars_select" on storage.objects;
create policy "room_avatars_select" on storage.objects for select using (bucket_id = 'room_avatars');

-- Only authenticated users can upload/update/delete their own room images
drop policy if exists "room_covers_insert" on storage.objects;
create policy "room_covers_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'room_covers');

drop policy if exists "room_covers_update" on storage.objects;
create policy "room_covers_update" on storage.objects for update to authenticated
  using (bucket_id = 'room_covers');

drop policy if exists "room_covers_delete" on storage.objects;
create policy "room_covers_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'room_covers');

drop policy if exists "room_avatars_insert" on storage.objects;
create policy "room_avatars_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'room_avatars');

drop policy if exists "room_avatars_update" on storage.objects;
create policy "room_avatars_update" on storage.objects for update to authenticated
  using (bucket_id = 'room_avatars');

drop policy if exists "room_avatars_delete" on storage.objects;
create policy "room_avatars_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'room_avatars');
