// =====================================================================
//  وصّلها — Edge Function: paymob-create-intention
//  Starts a wallet top-up: records a pending wallet_requests row (via the
//  existing request_deposit RPC — unchanged) then asks Paymob's Intention
//  API for a checkout URL. No secret keys ever reach the browser.
//
//  Deploy:   supabase functions deploy paymob-create-intention --no-verify-jwt
//  Secrets:  supabase secrets set PAYMOB_SECRET_KEY=... PAYMOB_PUBLIC_KEY=... \
//              PAYMOB_INTEGRATION_ID_CARD=... PAYMOB_INTEGRATION_ID_WALLET=... \
//              PAYMOB_INTEGRATION_ID_FAWRY=...
//  (PAYMOB_SECRET_KEY authorizes the server-side Intention API call;
//  PAYMOB_PUBLIC_KEY is embedded in the checkout URL — Paymob's dashboard
//  shows both separately under Developers → API Keys.)
//  (SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Paymob's Unified Checkout page itself offers the payer a method picker
// (card / mobile wallet / Fawry) when the intention lists more than one
// integration ID — so we don't need our own method selector in the UI.
const INTEGRATION_ENVS = [
  'PAYMOB_INTEGRATION_ID_CARD',
  'PAYMOB_INTEGRATION_ID_WALLET',
  'PAYMOB_INTEGRATION_ID_FAWRY',
];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { phone, amount } = await req.json();
    if (!phone || !amount) return json({ error: 'bad_request' }, 400);

    const PAYMOB_SECRET_KEY = Deno.env.get('PAYMOB_SECRET_KEY');
    const PAYMOB_PUBLIC_KEY = Deno.env.get('PAYMOB_PUBLIC_KEY');
    const paymentMethods = INTEGRATION_ENVS
      .map((name) => Deno.env.get(name))
      .filter((id): id is string => !!id)
      .map(Number);
    if (!PAYMOB_SECRET_KEY || !PAYMOB_PUBLIC_KEY || !paymentMethods.length) {
      return json({ error: 'gateway_not_configured' }, 500);
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Reuse the existing deposit-request RPC — validates the amount and
    // writes the pending row; does NOT touch the balance.
    const { data: reqRow, error: reqErr } = await admin.rpc('request_deposit', {
      p_phone: phone,
      p_amount: amount,
      p_method: 'Paymob (دفع أونلاين)',
      p_note: 'دفع أونلاين عبر Paymob',
    });
    if (reqErr || !reqRow) return json({ error: reqErr?.message || 'request_failed' }, 400);

    const intentionRes = await fetch('https://accept.paymob.com/v1/intention/', {
      method: 'POST',
      headers: {
        Authorization: `Token ${PAYMOB_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: Math.round(Number(amount) * 100), // Paymob wants EGP cents
        currency: 'EGP',
        payment_methods: paymentMethods,
        special_reference: reqRow.id,
        billing_data: {
          apartment: 'NA', floor: 'NA', building: 'NA', street: 'NA', city: 'NA',
          country: 'EG', state: 'NA',
          phone_number: phone,
          first_name: 'وصّلها', last_name: 'عميل',
          email: 'no-reply@wslha.co',
        },
        notification_url: `${Deno.env.get('SUPABASE_URL')}/functions/v1/paymob-webhook`,
      }),
    });

    if (!intentionRes.ok) {
      const detail = await intentionRes.text().catch(() => '');
      console.error('Paymob intention error:', intentionRes.status, detail);
      return json({ error: 'gateway_error' }, 502);
    }

    const intention = await intentionRes.json();
    const clientSecret = intention.client_secret;
    if (!clientSecret) return json({ error: 'gateway_error' }, 502);

    const iframeUrl = `https://accept.paymob.com/unifiedcheckout/?publicKey=${encodeURIComponent(PAYMOB_PUBLIC_KEY)}&clientSecret=${encodeURIComponent(clientSecret)}`;

    return json({ ok: true, request_id: reqRow.id, iframe_url: iframeUrl, client_secret: clientSecret });
  } catch (e) {
    console.error(e);
    return json({ error: 'server_error' }, 500);
  }

  function json(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
