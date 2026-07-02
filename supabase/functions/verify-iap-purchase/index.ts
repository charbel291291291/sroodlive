// ─────────────────────────────────────────────────────────────────────────────
// verify-iap-purchase — server-side IAP receipt verification (STUB).
//
// This is the ONLY place allowed to credit coins for an IAP purchase. Flow:
//   1. Client completes a store purchase and calls record_iap_purchase() to
//      create a PENDING receipt.
//   2. This function (or a cron/webhook) picks up pending receipts, verifies
//      the purchase token directly with Google Play Developer API / Apple
//      App Store Server API.
//   3. On success it calls fulfil_iap_purchase(receipt_id, true) with the
//      service_role key — the ONLY role allowed to run that RPC — which
//      credits coins from the server-owned catalog amount, idempotently.
//
// SECURITY: never trust the client's claim that a purchase is valid. Coins are
// credited only after this function confirms the token with the store. The
// real Google/Apple verification calls are intentionally left as TODOs — this
// stub wires the trusted path without granting anything yet.
// ─────────────────────────────────────────────────────────────────────────────

// deno-lint-ignore-file no-explicit-any
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  try {
    const { receipt_id } = await req.json().catch(() => ({}));
    if (!receipt_id) {
      return new Response(JSON.stringify({ error: "receipt_id required" }), {
        status: 400,
      });
    }

    // service_role client — required to run fulfil_iap_purchase (revoked from
    // anon/authenticated). Keys come from the function's environment.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // TODO: load the receipt, then verify purchase_token with the store:
    //   - Android: Google Play Developer API purchases.products.get
    //   - iOS: App Store Server API / verifyReceipt
    // Only set `verified = true` when the store confirms the purchase.
    const verified = false; // STUB: real verification not implemented yet.

    const { data, error } = await admin.rpc("fulfil_iap_purchase", {
      p_receipt_id: receipt_id,
      p_verified: verified,
      p_coins: null, // null => use the server catalog amount
    });
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true, result: data }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: String(e?.message ?? e) }), {
      status: 500,
    });
  }
});
