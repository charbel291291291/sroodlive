import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import { importPKCS8, SignJWT } from "jose";

type JsonObject = Record<string, unknown>;

interface PushRequest {
  notification_id?: string;
  user_id?: string;
  user_ids?: string[];
  title?: string;
  body?: string;
  data?: JsonObject;
  notification_type?: string;
  room_id?: string;
  sender_id?: string;
}

interface ResolvedPush {
  userIds: string[];
  title: string;
  body: string;
  data: JsonObject;
  notificationType: string;
  roomId?: string;
  senderId?: string;
}

interface TokenRow {
  id: string;
  token: string;
}

const jsonHeaders = { "Content-Type": "application/json" };
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const notificationTypePattern = /^[a-z0-9_.-]{1,64}$/i;
const maxUsersPerRequest = 100;
const maxTokensPerRequest = 1000;

let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function response(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;

  let difference = 0;
  for (let i = 0; i < leftBytes.length; i++) {
    difference |= leftBytes[i] ^ rightBytes[i];
  }
  return difference === 0;
}

function requireEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function cleanUuid(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const cleaned = value.trim();
  return uuidPattern.test(cleaned) ? cleaned : undefined;
}

function validateText(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (typeof value !== "string") {
    throw new TypeError(`${field} must be a string`);
  }
  const cleaned = value.trim();
  if (!cleaned || cleaned.length > maxLength) {
    throw new TypeError(`${field} must be 1-${maxLength} characters`);
  }
  return cleaned;
}

function normalizeData(data: JsonObject): Record<string, string> {
  const normalized: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (!/^[a-zA-Z0-9_.-]{1,64}$/.test(key) || value === undefined) continue;
    if (typeof value === "string") {
      normalized[key] = value.slice(0, 1000);
    } else if (
      typeof value === "number" ||
      typeof value === "boolean" ||
      value === null
    ) {
      normalized[key] = String(value);
    } else {
      normalized[key] = JSON.stringify(value).slice(0, 1000);
    }
  }
  return normalized;
}

async function getGoogleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60) {
    return cachedAccessToken.value;
  }

  const clientEmail = requireEnvironment("FCM_CLIENT_EMAIL");
  const privateKey = requireEnvironment("FCM_PRIVATE_KEY").replace(/\\n/g, "\n");
  const signingKey = await importPKCS8(privateKey, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(signingKey);

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!tokenResponse.ok) {
    throw new Error(`FCM OAuth failed with status ${tokenResponse.status}`);
  }

  const tokenJson = await tokenResponse.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!tokenJson.access_token) throw new Error("FCM OAuth returned no token");

  cachedAccessToken = {
    value: tokenJson.access_token,
    expiresAt: now + Math.max(60, tokenJson.expires_in ?? 3600),
  };
  return cachedAccessToken.value;
}

async function resolvePush(
  payload: PushRequest,
  supabaseAdmin: SupabaseClient<any, "public", any>,
): Promise<ResolvedPush> {
  const notificationId = cleanUuid(payload.notification_id);
  if (payload.notification_id && !notificationId) {
    throw new TypeError("notification_id must be a UUID");
  }

  if (notificationId) {
    const { data, error } = await supabaseAdmin
      .from("notifications")
      .select("user_id, title, body, type, actor_id, target_id")
      .eq("id", notificationId)
      .maybeSingle();

    if (error) throw new Error("Could not load notification");
    if (!data) throw new TypeError("notification_id was not found");

    const targetUserId = cleanUuid(data.user_id);
    if (!targetUserId) throw new TypeError("notification has invalid user_id");

    return {
      userIds: [targetUserId],
      title: validateText(data.title, "title", 200),
      body: validateText(data.body, "body", 1000),
      notificationType: validateText(
        data.type ?? "system",
        "notification_type",
        64,
      ),
      data: {
        notification_id: notificationId,
        actor_id: data.actor_id,
        target_id: data.target_id,
      },
    };
  }

  const candidateIds = [
    ...(Array.isArray(payload.user_ids) ? payload.user_ids : []),
    ...(payload.user_id ? [payload.user_id] : []),
  ];
  if (
    candidateIds.length === 0 ||
    candidateIds.length > maxUsersPerRequest ||
    candidateIds.some((value) => !cleanUuid(value))
  ) {
    throw new TypeError("user_id or user_ids must contain valid UUIDs");
  }
  const userIds = [...new Set(candidateIds.map((value) => cleanUuid(value)!))];

  const notificationType = validateText(
    payload.notification_type,
    "notification_type",
    64,
  );
  if (!notificationTypePattern.test(notificationType)) {
    throw new TypeError("notification_type contains invalid characters");
  }
  if (
    payload.data !== undefined &&
    (payload.data === null ||
      Array.isArray(payload.data) ||
      typeof payload.data !== "object")
  ) {
    throw new TypeError("data must be an object");
  }

  const roomId = payload.room_id ? cleanUuid(payload.room_id) : undefined;
  const senderId = payload.sender_id ? cleanUuid(payload.sender_id) : undefined;
  if (payload.room_id && !roomId) throw new TypeError("room_id must be a UUID");
  if (payload.sender_id && !senderId) {
    throw new TypeError("sender_id must be a UUID");
  }

  return {
    userIds,
    title: validateText(payload.title, "title", 200),
    body: validateText(payload.body, "body", 1000),
    data: payload.data ?? {},
    notificationType,
    roomId,
    senderId,
  };
}

function isInvalidTokenResponse(status: number, body: string): boolean {
  if (status !== 400 && status !== 404) return false;
  return body.includes("UNREGISTERED") ||
    body.includes("registration-token-not-registered");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }

  const expectedSecret = Deno.env.get("PUSH_INTERNAL_SECRET") ?? "";
  const suppliedSecret = req.headers.get("x-push-secret") ?? "";
  if (
    !expectedSecret ||
    !suppliedSecret ||
    !constantTimeEqual(expectedSecret, suppliedSecret)
  ) {
    return response(401, { error: "unauthorized" });
  }

  try {
    const supabaseUrl = requireEnvironment("SUPABASE_URL");
    const serviceRoleKey = requireEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const projectId = requireEnvironment("FCM_PROJECT_ID");
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let rawPayload: unknown;
    try {
      rawPayload = await req.json();
    } catch {
      return response(400, { error: "invalid_json" });
    }
    if (
      rawPayload === null ||
      Array.isArray(rawPayload) ||
      typeof rawPayload !== "object"
    ) {
      return response(400, { error: "invalid_payload" });
    }

    let push: ResolvedPush;
    try {
      push = await resolvePush(rawPayload as PushRequest, supabaseAdmin);
    } catch (error) {
      if (error instanceof TypeError) {
        return response(400, { error: error.message });
      }
      throw error;
    }

    const { data: settingsRows, error: settingsError } = await supabaseAdmin
      .from("user_settings")
      .select("user_id, notifications_enabled")
      .in("user_id", push.userIds);
    if (settingsError) throw new Error("Could not load notification settings");

    const disabledUserIds = new Set(
      (settingsRows ?? [])
        .filter((row) => row.notifications_enabled === false)
        .map((row) => String(row.user_id)),
    );
    const enabledUserIds = push.userIds.filter((id) => !disabledUserIds.has(id));
    if (enabledUserIds.length === 0) {
      return response(200, {
        sent: 0,
        failed: 0,
        invalid_token_count: 0,
      });
    }

    const { data: tokenRows, error: tokenError } = await supabaseAdmin
      .from("user_push_tokens")
      .select("id, token")
      .in("user_id", enabledUserIds)
      .eq("is_active", true)
      .order("last_seen_at", { ascending: false })
      .limit(maxTokensPerRequest);

    if (tokenError) throw new Error("Could not load push tokens");
    const tokens = (tokenRows ?? []) as TokenRow[];
    if (tokens.length === 0) {
      return response(200, {
        sent: 0,
        failed: 0,
        invalid_token_count: 0,
      });
    }

    const accessToken = await getGoogleAccessToken();
    const invalidTokenIds: string[] = [];
    let sent = 0;
    let failed = 0;

    const baseData = normalizeData({
      ...push.data,
      notification_type: push.notificationType,
      room_id: push.roomId,
      sender_id: push.senderId,
    });

    for (let offset = 0; offset < tokens.length; offset += 25) {
      const batch = tokens.slice(offset, offset + 25);
      const results = await Promise.all(
        batch.map(async (row) => {
          const fcmResponse = await fetch(
            `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${accessToken}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                message: {
                  token: row.token,
                  notification: {
                    title: push.title,
                    body: push.body,
                  },
                  data: baseData,
                  android: { priority: "high" },
                  apns: {
                    payload: { aps: { sound: "default" } },
                  },
                },
              }),
            },
          );
          if (fcmResponse.ok) return { sent: true, invalid: false, id: row.id };

          const errorBody = await fcmResponse.text();
          return {
            sent: false,
            invalid: isInvalidTokenResponse(fcmResponse.status, errorBody),
            id: row.id,
          };
        }),
      );

      for (const result of results) {
        if (result.sent) {
          sent++;
        } else {
          failed++;
          if (result.invalid) invalidTokenIds.push(result.id);
        }
      }
    }

    if (invalidTokenIds.length > 0) {
      const { error: invalidateError } = await supabaseAdmin
        .from("user_push_tokens")
        .update({
          is_active: false,
          invalidated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .in("id", invalidTokenIds);
      if (invalidateError) {
        console.error("[Push] Failed to deactivate invalid tokens");
      }
    }

    return response(200, {
      sent,
      failed,
      invalid_token_count: invalidTokenIds.length,
    });
  } catch (error) {
    console.error("[Push] Delivery failed", error);
    return response(500, { error: "push_delivery_failed" });
  }
});
