-- Storage policies for admin-assets bucket.
-- Public read depends on bucket public setting.
-- Write access is limited to super_admin and content_admin.

drop policy if exists "admin_assets_select" on storage.objects;
create policy "admin_assets_select"
  on storage.objects for select to authenticated
  using (bucket_id = 'admin-assets');

drop policy if exists "admin_assets_insert" on storage.objects;
create policy "admin_assets_insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'admin-assets'
    and (public.has_app_role('super_admin') or public.has_app_role('content_admin'))
  );

drop policy if exists "admin_assets_update" on storage.objects;
create policy "admin_assets_update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'admin-assets'
    and (public.has_app_role('super_admin') or public.has_app_role('content_admin'))
  );

drop policy if exists "admin_assets_delete" on storage.objects;
create policy "admin_assets_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'admin-assets'
    and (public.has_app_role('super_admin') or public.has_app_role('content_admin'))
  );