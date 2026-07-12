-- Tighten public_user_id format rules:
--   Normal / Golden IDs : ^[a-z0-9_]{2,30}$   (lowercase, no SR prefix, no dash)
--   Admin SR IDs        : ^SR[0-9]{1,28}$      (uppercase SR + digits only)
--
-- IMPORTANT: This migration will fail if any non-admin profile still holds an
-- SR-format ID (e.g. SR666, SR1010, SR10452, SR00000003, SR00000006).
-- Update or clear those rows first, then apply this migration.
--
-- To identify affected rows before running:
--   SELECT id, public_user_id FROM public.profiles
--   WHERE public_user_id ~ '^[Ss][Rr][0-9]+'
--     AND id NOT IN (SELECT user_id FROM public.admin_users);

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_public_user_id_format;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_public_user_id_format
  CHECK (
    public_user_id ~ '^SR[0-9]{1,28}$'
    OR public_user_id ~ '^[a-z0-9_]{2,30}$'
  );
