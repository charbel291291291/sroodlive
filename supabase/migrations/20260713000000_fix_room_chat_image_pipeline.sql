-- ============================================================================
-- Fix room chat image upload/send pipeline
-- Ensures bucket, policies, VIP permission gate, and send RPC are correct.
-- ============================================================================

-- 1. Ensure message columns exist
alter table public.room_messages
  add column if not exists image_url text,
  add column if not exists image_path text;

-- 2. Ensure storage bucket exists
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'room_chat_images',
  'room_chat_images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- 3. Fresh backend permission gate
create or replace function public.can_user_send_chat_image(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and coalesce(p.vip_level, 0) >= 7
      and (p.vip_expires_at is null or p.vip_expires_at > now())
  )
  or public.has_admin_access();
$$;

grant execute on function public.can_user_send_chat_image(uuid) to authenticated;

-- 4. Storage policies
drop policy if exists "room_chat_images_read" on storage.objects;
create policy "room_chat_images_read"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'room_chat_images');

drop policy if exists "room_chat_images_upload_vip7" on storage.objects;
create policy "room_chat_images_upload_vip7"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'room_chat_images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and public.can_user_send_chat_image(auth.uid())
);

drop policy if exists "room_chat_images_delete_own" on storage.objects;
create policy "room_chat_images_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'room_chat_images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 5. Replace image-message RPC
DROP FUNCTION IF EXISTS public.send_room_image_message(uuid, text, text, text);

create or replace function public.send_room_image_message(
  p_room_id uuid,
  p_image_url text,
  p_image_path text,
  p_sender_role text default 'listener'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_message_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if not public.can_user_send_chat_image(v_user_id) then
    raise exception 'image_messages_unlock_at_vip_7';
  end if;

  if p_room_id is null then
    raise exception 'missing_room_id';
  end if;

  if coalesce(trim(p_image_url), '') = '' then
    raise exception 'missing_image_url';
  end if;

  if coalesce(trim(p_image_path), '') = '' then
    raise exception 'missing_image_path';
  end if;

  if split_part(p_image_path, '/', 1) <> v_user_id::text then
    raise exception 'invalid_image_path_owner';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = v_user_id;

  insert into public.room_messages (
    room_id,
    sender_id,
    sender_name,
    sender_avatar_url,
    sender_vip_level,
    sender_role,
    message,
    message_type,
    image_url,
    image_path
  )
  values (
    p_room_id,
    v_user_id,
    coalesce(nullif(v_profile.display_name, ''), nullif(v_profile.username, ''), 'User'),
    v_profile.avatar_url,
    coalesce(v_profile.vip_level, 0),
    coalesce(nullif(p_sender_role, ''), 'listener'),
    '',
    'image',
    p_image_url,
    p_image_path
  )
  returning id into v_message_id;

  return jsonb_build_object(
    'id', v_message_id,
    'room_id', p_room_id,
    'image_url', p_image_url,
    'image_path', p_image_path
  );
end;
$$;

grant execute on function public.send_room_image_message(uuid, text, text, text) to authenticated;

