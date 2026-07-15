// Verifies that a Stripe Checkout Session was actually paid, without needing
// a database -- Stripe is the single source of truth for whether Neura
// Premium should unlock. Serves two audiences from one endpoint:
//   - Browser (Stripe's post-payment redirect, Accept: text/html) -> a
//     small page showing the session id as the code to paste into the app.
//   - The app itself (Accept: application/json) -> {"valid": true/false}.
//
// Deploy:  supabase functions deploy verify-purchase --no-verify-jwt
// Secret:  supabase secrets set STRIPE_SECRET_KEY=sk_...
//
// No per-device/per-purchase redemption limit is enforced here -- the
// "code" is the Stripe session id itself, and anyone holding it can redeem
// it on any install. Deliberate trade-off for personal/small-circle scale;
// see the monetization plan for context.

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";

async function isSessionPaid(sessionId: string): Promise<boolean> {
  if (!sessionId || !STRIPE_SECRET_KEY) return false;
  const res = await fetch(
    `https://api.stripe.com/v1/checkout/sessions/${encodeURIComponent(sessionId)}`,
    { headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` } },
  );
  if (!res.ok) return false;
  const session = await res.json();
  return session.payment_status === "paid";
}

function htmlPage(valid: boolean, sessionId: string): string {
  const body = valid
    ? `
      <h1>Thank you!</h1>
      <p>Your purchase is confirmed. Copy the code below into Neura's
      Settings &rarr; Premium screen to unlock it:</p>
      <pre style="font-size:1.1rem;background:#111;color:#0f0;padding:12px;
      border-radius:8px;user-select:all;word-break:break-all;">${sessionId}</pre>
    `
    : `
      <h1>We couldn't confirm this purchase</h1>
      <p>If you just paid, this can take a few seconds -- try refreshing.
      If it still doesn't work, contact support with this reference:
      ${sessionId || "(none provided)"}</p>
    `;
  return `<!doctype html><html><head><meta charset="utf-8">
    <title>Neura Premium</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>body{font-family:system-ui,sans-serif;max-width:520px;
    margin:48px auto;padding:0 16px;background:#0d0d14;color:#eee;}
    a{color:#8ab4ff;}</style>
    </head><body>${body}</body></html>`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET, OPTIONS",
        "access-control-allow-headers": "accept, content-type",
      },
    });
  }

  const url = new URL(req.url);
  const sessionId = url.searchParams.get("session_id") ?? "";
  const wantsHtml = (req.headers.get("accept") ?? "").includes("text/html");

  const valid = await isSessionPaid(sessionId);

  if (wantsHtml) {
    return new Response(htmlPage(valid, sessionId), {
      headers: { "content-type": "text/html; charset=utf-8" },
      status: 200,
    });
  }

  return new Response(JSON.stringify({ valid }), {
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    },
    status: 200,
  });
});
