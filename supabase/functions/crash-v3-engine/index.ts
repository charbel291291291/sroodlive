import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

const LOOP_INTERVAL_MS = 200;
const MAX_RUN_MS = 50_000;

type EngineWork = {
  server_time: string;
  round: null | {
    id: string;
    status: string;
    encrypted_server_seed: string;
    server_seed_hash: string;
    client_seed: string;
    nonce: number;
  };
};

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index++) {
    difference |= (a[index % Math.max(a.length, 1)] ?? 0) ^
      (b[index % Math.max(b.length, 1)] ?? 0);
  }
  return difference === 0;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function encryptionKey(): Promise<CryptoKey> {
  const raw = base64ToBytes(requiredEnv("CRASH_V3_SEED_ENCRYPTION_KEY"));
  if (raw.byteLength !== 32) {
    throw new Error("CRASH_V3_SEED_ENCRYPTION_KEY must decode to 32 bytes");
  }
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function encryptSeed(seed: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv }, await encryptionKey(), new TextEncoder().encode(seed),
  ));
  return `v1.${bytesToBase64(iv)}.${bytesToBase64(encrypted)}`;
}

async function decryptSeed(payload: string): Promise<string> {
  const [version, ivValue, cipherValue] = payload.split(".");
  if (version !== "v1" || !ivValue || !cipherValue) {
    throw new Error("Unsupported encrypted seed payload");
  }
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64ToBytes(ivValue) },
    await encryptionKey(),
    base64ToBytes(cipherValue),
  );
  return new TextDecoder().decode(decrypted);
}

async function rpc<T>(client: SupabaseClient, name: string, params: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(name, params);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data as T;
}

async function tick(client: SupabaseClient, instanceId: string): Promise<Record<string, unknown>> {
  const work = await rpc<EngineWork>(client, "crash_v3_engine_get_work", {
    p_engine_instance_id: instanceId,
  });
  if (!work.round) {
    const seed = bytesToHex(crypto.getRandomValues(new Uint8Array(32)));
    return await rpc(client, "crash_v3_engine_tick", {
      p_engine_instance_id: instanceId,
      p_new_server_seed: seed,
      p_new_encrypted_server_seed: await encryptSeed(seed),
      p_current_server_seed: null,
    });
  }
  return await rpc(client, "crash_v3_engine_tick", {
    p_engine_instance_id: instanceId,
    p_new_server_seed: null,
    p_new_encrypted_server_seed: null,
    p_current_server_seed: await decryptSeed(work.round.encrypted_server_seed),
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }
  try {
    const suppliedSecret = request.headers.get("x-crash-engine-secret") ?? "";
    if (!constantTimeEqual(suppliedSecret, requiredEnv("CRASH_V3_ENGINE_SECRET"))) {
      return Response.json({ error: "unauthorized" }, { status: 401 });
    }
    const client = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const instanceId = requiredEnv("CRASH_V3_ENGINE_INSTANCE_ID");
    const deadline = Date.now() + MAX_RUN_MS;
    let lastResult: Record<string, unknown> = {};
    let ticks = 0;
    while (Date.now() < deadline && !request.signal.aborted) {
      try {
        lastResult = await tick(client, instanceId);
        ticks++;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.includes("engine_lease_owned") || message.includes("engine_busy")) {
          return Response.json({ status: "standby", instance_id: instanceId, ticks });
        }
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, LOOP_INTERVAL_MS));
    }
    return Response.json({ status: "ok", instance_id: instanceId, ticks, last_result: lastResult });
  } catch (error) {
    console.error("Crash V3 engine failure", error);
    return Response.json({
      error: "engine_failure",
      message: error instanceof Error ? error.message : String(error),
    }, { status: 500 });
  }
});
