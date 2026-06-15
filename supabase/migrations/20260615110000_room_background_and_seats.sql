-- Add background_url column to rooms table
alter table public.rooms
  add column if not exists background_url text null;

-- Storage bucket for room backgrounds
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'room-backgrounds',
  'room-backgrounds',
  true,
  10485760,  -- 10 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Drop and recreate storage policies to avoid conflicts
do $$
begin
  drop policy if exists "Authenticated users can upload room backgrounds" on storage.objects;
  drop policy if exists "Authenticated users can update room backgrounds" on storage.objects;
  drop policy if exists "Public read for room backgrounds" on storage.objects;
end$$;

create policy "Authenticated users can upload room backgrounds"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'room-backgrounds');

create policy "Authenticated users can update room backgrounds"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'room-backgrounds');

create policy "Public read for room backgrounds"
  on storage.objects for select
  to public
  using (bucket_id = 'room-backgrounds');
