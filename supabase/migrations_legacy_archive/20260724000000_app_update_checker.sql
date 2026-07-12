create table if not exists public.app_versions (
  id text primary key,
  platform text not null default 'android',
  version_code integer not null,
  version_name text not null,
  apk_url text not null,
  release_notes text,
  force_update boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.app_versions enable row level security;

drop policy if exists app_versions_select_active_anon on public.app_versions;
drop policy if exists app_versions_select_active_auth on public.app_versions;

create policy app_versions_select_active_anon
on public.app_versions
for select
to anon
using (is_active = true);

create policy app_versions_select_active_auth
on public.app_versions
for select
to authenticated
using (is_active = true);

grant select on public.app_versions to anon;
grant select on public.app_versions to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'app_releases',
  'app_releases',
  true,
  200000000,
  array[
    'application/vnd.android.package-archive',
    'application/octet-stream'
  ]
)
on conflict (id) do update set
  public = true,
  file_size_limit = 200000000,
  allowed_mime_types = array[
    'application/vnd.android.package-archive',
    'application/octet-stream'
  ];
