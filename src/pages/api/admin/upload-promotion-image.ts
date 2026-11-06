// وصّلها — POST /api/admin/upload-promotion-image
// The `promotions` storage bucket used to have an "anon upload" INSERT
// policy — ANYONE could POST an arbitrary file straight to
// /storage/v1/object/promotions/* with no auth at all (security-175).
// That policy is now removed; this route is the only way to add an image
// to the bucket, gated by the same admin phone+password check every
// admin_* RPC uses (admin_verify_password, verified here before ever
// touching the service-role key) — same pattern as sign-document.ts.
import type { APIRoute } from 'astro';
import { SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

function requireEnv(name: string): string {
  const v = import.meta.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export const POST: APIRoute = async ({ request }) => {
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return new Response(JSON.stringify({ error: 'bad_form' }), { status: 400 });
  }
  const adminPhone = form.get('adminPhone');
  const adminPassword = form.get('adminPassword');
  const file = form.get('file');
  if (
    typeof adminPhone !== 'string' || !adminPhone ||
    typeof adminPassword !== 'string' || !adminPassword ||
    !(file instanceof File)
  ) {
    return new Response(JSON.stringify({ error: 'missing_fields' }), { status: 400 });
  }
  // 5MB cap — these are campaign/popup images, never meant to be huge.
  if (file.size > 5 * 1024 * 1024) {
    return new Response(JSON.stringify({ error: 'file_too_large' }), { status: 400 });
  }

  const verifyRes = await fetch(`${SB_URL}/rest/v1/rpc/admin_verify_password`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_admin_phone: adminPhone, p_admin_password: adminPassword }),
  });
  const verified = verifyRes.ok && (await verifyRes.json()) === true;
  if (!verified) {
    return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 });
  }

  let serviceKey: string;
  try {
    serviceKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  } catch {
    return new Response(JSON.stringify({ error: 'server_misconfigured' }), { status: 500 });
  }

  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
  const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${safeName}`;
  const buf = await file.arrayBuffer();
  const uploadRes = await fetch(`${SB_URL}/storage/v1/object/promotions/${path}`, {
    method: 'POST',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': file.type || 'application/octet-stream',
    },
    body: buf,
  });
  if (!uploadRes.ok) {
    return new Response(JSON.stringify({ error: 'upload_failed' }), { status: 502 });
  }

  const url = `${SB_URL}/storage/v1/object/public/promotions/${path}`;
  return new Response(JSON.stringify({ url }), { status: 200, headers: { 'Content-Type': 'application/json' } });
};
