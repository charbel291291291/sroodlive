-- Helper: returns true only when both users follow each other
CREATE OR REPLACE FUNCTION public.are_mutual_friends(user_a uuid, user_b uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_follows
    WHERE follower_id = user_a AND following_id = user_b
  ) AND EXISTS (
    SELECT 1 FROM public.user_follows
    WHERE follower_id = user_b AND following_id = user_a
  );
$$;

GRANT EXECUTE ON FUNCTION public.are_mutual_friends(uuid, uuid) TO authenticated;

-- Enforce mutual follow before creating a new conversation
DROP POLICY IF EXISTS "private_conversations_insert_member" ON public.private_conversations;
DROP POLICY IF EXISTS "private_conversations_insert_mutual_friends" ON public.private_conversations;

CREATE POLICY "private_conversations_insert_mutual_friends"
ON public.private_conversations
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IN (user_one_id, user_two_id)
  AND public.are_mutual_friends(user_one_id, user_two_id)
);

-- Enforce mutual follow before sending a message
DROP POLICY IF EXISTS "private_messages_insert_sender" ON public.private_messages;
DROP POLICY IF EXISTS "private_messages_insert_mutual_friends" ON public.private_messages;

CREATE POLICY "private_messages_insert_mutual_friends"
ON public.private_messages
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = sender_id
  AND EXISTS (
    SELECT 1 FROM public.private_conversations
    WHERE id = conversation_id
      AND (user_one_id = auth.uid() OR user_two_id = auth.uid())
  )
  AND public.are_mutual_friends(sender_id, receiver_id)
);

