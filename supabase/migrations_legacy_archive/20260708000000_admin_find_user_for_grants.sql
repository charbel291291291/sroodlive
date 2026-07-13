-- =============================================================================
-- Admin: Find User For VIP Grants — Phase V1 support
--
-- Problem:
--   The VIP Admin Panel previously accepted raw text as a user ID and passed
--   it directly to grant_vip(p_user_id uuid), causing:
--     "invalid input syntax for type uuid" when admins entered e.g. "007"
--
-- Solution:
--   admin_find_user_for_grants(p_query, p_limit) resolves any of:
--     - UUID string      → exact match on profiles.id
--     - Golden ID (007)  → exact match on profiles.public_user_id
--     - username         → ilike match
--     - display_name     → ilike match
--   Returns resolved user_id (UUID) + display fields for the selection card.
--   The Flutter layer then passes ONLY the resolved UUID to grant_vip / etc.
--
-- Safety:
--   Never casts p_query directly to uuid.
--   UUID detection via regex — cast only after match is confirmed.
--
-- Auth:
--   Caller must satisfy public.has_admin_access() (same guard as admin_search_users).
--   GRANT to authenticated; REVOKE from anon.
--   SECURITY DEFINER with fixed search_path.
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_find_user_for_grants(
  p_query  text,
  p_limit  integer DEFAULT 10
)
RETURNS TABLE (
  user_id      uuid,
  username     text,
  display_name text,
  golden_id    text,
  avatar_url   text,
  vip_level    integer,
  vip_until    timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_query  text := trim(coalesce(p_query, ''));
  v_limit  int  := greatest(1, least(coalesce(p_limit, 10), 50));
  v_is_uuid boolean;
BEGIN
  IF NOT public.has_admin_access() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_query = '' THEN
    RETURN;
  END IF;

  -- Safe UUID detection — regex only, no cast attempted before confirmation.
  v_is_uuid := v_query ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.display_name,
    p.public_user_id,   -- this is the "golden_id" / public short-code
    p.avatar_url,
    COALESCE(p.vip_level, 0),
    p.vip_expires_at
  FROM public.profiles p
  WHERE
    CASE
      -- Branch 1: query looks like a UUID → exact id match
      WHEN v_is_uuid THEN
        p.id = v_query::uuid

      -- Branch 2: exact golden-ID / public-user-id match (e.g. "007")
      WHEN p.public_user_id = v_query THEN
        true

      -- Branch 3: fuzzy name / username / partial UUID-text match
      ELSE
        p.public_user_id ilike '%' || v_query || '%'
        OR p.username     ilike '%' || v_query || '%'
        OR p.display_name ilike '%' || v_query || '%'
        OR p.id::text     ilike '%' || v_query || '%'
    END
  ORDER BY
    -- Exact matches first
    (p.public_user_id = v_query) DESC,
    (v_is_uuid AND p.id = v_query::uuid) DESC,
    p.created_at DESC
  LIMIT v_limit;
END;
$$;

GRANT  EXECUTE ON FUNCTION public.admin_find_user_for_grants(text, integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_find_user_for_grants(text, integer) FROM anon;

-- =============================================================================
-- End.
--
-- RPC:
--   admin_find_user_for_grants(p_query text, p_limit int DEFAULT 10)
--   → TABLE(user_id, username, display_name, golden_id, avatar_url,
--            vip_level, vip_until)
--
-- Search priority:
--   1. UUID exact match (regex-validated, never blind cast)
--   2. golden_id (public_user_id) exact match
--   3. username / display_name / UUID-fragment ilike
--
-- Flutter usage:
--   AdminService.findUsersForGrants(query) → List<AdminUserSummary>
--   Selected user's .userId (UUID) is passed to grantVip / revokeVip / setGoldenId.
-- =============================================================================
