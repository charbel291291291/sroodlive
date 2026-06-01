import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function base64UrlEncode(input: string | Uint8Array) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

async function signJwt(payload: Record<string, unknown>, secret: string) {
  const header = { alg: "HS256", typ: "JWT" };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(data),
  );

  return `${data}.${base64UrlEncode(new Uint8Array(signature))}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const livekitApiKey = Deno.env.get("LIVEKIT_API_KEY");
    const livekitApiSecret = Deno.env.get("LIVEKIT_API_SECRET");
    const livekitWsUrl = Deno.env.get("LIVEKIT_WS_URL");

    if (!supabaseUrl || !supabaseAnonKey) {
      throw new Error("Missing Supabase environment variables.");
    }

    if (!livekitApiKey || !livekitApiSecret || !livekitWsUrl) {
      throw new Error("Missing LiveKit environment variables.");
    }

    const authorization = req.headers.get("Authorization");

    if (!authorization) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authorization },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const roomId = String(body.room_id ?? "");

    if (!roomId) {
      return new Response(JSON.stringify({ error: "room_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: room, error: roomError } = await supabase
      .from("rooms")
      .select("id, livekit_room_name")
      .eq("id", roomId)
      .single();

    if (roomError || !room) {
      return new Response(JSON.stringify({ error: "Room not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    await supabase.from("room_members").upsert(
      {
        room_id: roomId,
        user_id: user.id,
        role: "listener",
        left_at: null,
      },
      { onConflict: "room_id,user_id" },
    );

    const now = Math.floor(Date.now() / 1000);
    const livekitRoomName = room.livekit_room_name || `srood_${room.id}`;

    const token = await signJwt(
      {
        iss: livekitApiKey,
        sub: user.id,
        name: user.email ?? user.id,
        nbf: now - 10,
        exp: now + 3600,
        video: {
          roomJoin: true,
          room: livekitRoomName,
          canPublish: true,
          canSubscribe: true,
          canPublishData: true,
        },
      },
      livekitApiSecret,
    );

    return new Response(
      JSON.stringify({
        token,
        url: livekitWsUrl,
        roomName: livekitRoomName,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
