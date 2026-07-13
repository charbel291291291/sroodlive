-- Widen public_user_id check constraint so Golden IDs assigned via
-- set_custom_golden_id (format ^[A-Za-z0-9_-]{2,20}$) don't crash against
-- the old restrictive constraint (^SR[0-9]+$ or ^[1-9][0-9]{5}$).
-- All existing SR + digit IDs still satisfy the new rule.

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_public_user_id_format;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_public_user_id_format
  CHECK (public_user_id ~ '^[A-Za-z0-9_-]{2,30}$');
