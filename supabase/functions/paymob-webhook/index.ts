// =====================================================================
//  وصّلها — Edge Function: paymob-webhook
//  Paymob calls this after a transaction is processed. We verify the HMAC,
//  find the matching wallet_requests row, and — only on a verified success —
//  log the transaction then move the balance, exactly like the admin panel's
//  manual "log first, then credit" flow (admin.astro: log_wallet_transaction
//  followed by add_wallet_balance). Idempotent: a row already 'done' is a
//  no-op, since Paymob may resend the callback.
//
//  Deploy:   supabase functions deploy paymob-webhook --no-verify-jwt
//  Secrets:  supabase secrets set PAYMOB_HMAC_SECRET=...
//  Paymob dashboard: set this function's URL as the transaction
//  "Processed Callback" / webhook URL.
//
//  NOTE: Paymob's HMAC field order below matches their published
//  transaction-callback spec. Verify against a real sandbox payload before
//  going live — Paymob has changed payload shape between API versions.
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const HMAC_FIELDS = [
  'amount_cents', 'created_at', 'currency', 'error_occured',
  'has_parent_transaction', 'id', 'integration_id', 'is_3d_secure',
  'is_auth', 'is_capture', 'is_refunded', 'is_standalone_payment',
  'is_voided', 'order.id', 'owner', 'pending',
  'source_data.pan', 'source_data.sub_type', 'source_data.type', 'success',
];

function pick(obj: Record<string, unknown>, path: string): unknown {
  return path.split('.').reduce<unknown>((v, k) => (v as Record<string, unknown> | undefined)?.[k], obj);
}

async function verifyHmac(obj: Record<string, unknown>, hmacParam: string, secret: string): Promise<boolean> {
  const concatenated = HMAC_FIELDS.map((f) => {
    const v = pick(obj, f);
    return v === undefined || v === null ? '' : String(v);
  }).join('');

  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-512' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(concatenated));
  const hex = [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return hex === hmacParam;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });

  try {
    const url = new URL(req.url);
    const hmacParam = url.searchParams.get('hmac') || '';
    const HMAC_SECRET = Deno.env.get('PAYMOB_HMAC_SECRET');
    if (!HMAC_SECRET) return new Response('gateway not configured', { status: 500 });

    const body = await req.json();
    const obj = body?.obj ?? body; // Paymob wraps the transaction in `obj`

    const validHmac = await verifyHmac(obj, hmacParam, HMAC_SECRET);
    if (!validHmac) {
      console.error('paymob-webhook: HMAC mismatch');
      return new Response('forbidden', { status: 403 });
    }

    const specialRef: string | undefined = obj?.order?.merchant_order_id ?? obj?.order?.special_reference;
    const success: boolean = obj?.success === true || obj?.success === 'true';
    if (!specialRef) return new Response('no reference', { status: 400 });

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: reqRow, error: findErr } = await admin
      .from('wallet_requests').select('*').eq('id', specialRef).maybeSingle();
    if (findErr || !reqRow) return new Response('request not found', { status: 404 });

    if (reqRow.status !== 'pending') {
      // Already processed (retry from Paymob) — acknowledge without repeating the credit.
      return Response.json({ ok: true, already_processed: true });
    }

    if (!success) {
      await admin.from('wallet_requests')
        .update({ status: 'rejected', processed_at: new Date().toISOString() })
        .eq('id', specialRef);
      return Response.json({ ok: true, status: 'rejected' });
    }

    const txId = `pmb-${obj.id}`;
    const { error: logErr } = await admin.rpc('log_wallet_transaction', {
      p_id: txId,
      p_phone: reqRow.phone,
      p_amount: reqRow.amount,
      p_type: 'deposit', // log_wallet_transaction's check constraint doesn't allow 'topup'
      p_reference_id: reqRow.id,
      p_note: `شحن أونلاين عبر Paymob (معاملة #${obj.id})`,
    });
    if (logErr) {
      console.error('paymob-webhook: log_wallet_transaction failed', logErr.message);
      return new Response('log failed', { status: 500 });
    }

    const { error: balErr } = await admin.rpc('add_wallet_balance', {
      p_phone: reqRow.phone,
      p_amount: reqRow.amount,
    });
    if (balErr) {
      console.error('paymob-webhook: add_wallet_balance failed', balErr.message);
      return new Response('credit failed', { status: 500 });
    }

    await admin.from('wallet_requests')
      .update({ status: 'done', processed_at: new Date().toISOString() })
      .eq('id', specialRef);

    return Response.json({ ok: true, status: 'done' });
  } catch (e) {
    console.error(e);
    return new Response('server error', { status: 500 });
  }
});
