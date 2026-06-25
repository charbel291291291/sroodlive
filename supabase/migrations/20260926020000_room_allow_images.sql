-- Allow room owner to toggle whether users can send images in chat.
alter table public.rooms
  add column if not exists allow_images boolean not null default true;
