// وصّلها — POST /api/admin/sign-document
// Driver/merchant identity documents uploaded after security-125 live in
// the private `driver-docs` storage bucket — the admin review UI
// (admin.astro's driver/merchant modal) can't just use a stored public
// URL for them anymore, so it calls this route for a short-lived signed
// URL per document instead. Gated by the same admin phone+password
// check every other admin_* RPC uses (admin_verify_password), verified
// here before ever touching the service-role key.
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
  let body: { adminPhone?: string; adminPassword?: string; paths?: string[] };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400 });
  }
  const { adminPhone, adminPassword, paths } = body;
  if (!adminPhone || !adminPassword || !Array.isArray(paths) || paths.length === 0) {
    return new Response(JSON.stringify({ error: 'missing_fields' }), { status: 400 });
  }
  // storage paths only — this is a signing endpoint, not a general
  // document-serving proxy, so reject anything that isn't a plain
  // relative path under driver-docs (no scheme, no traversal).
  if (paths.some((p) => typeof p !== 'string' || !p || p.includes('..') || /^[a-z]+:\/\//i.test(p))) {
    return new Response(JSON.stringify({ error: 'bad_path' }), { status: 400 });
  }
  if (paths.length > 30) {
    return new Response(JSON.stringify({ error: 'too_many_paths' }), { status: 400 });
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

  const signRes = await fetch(`${SB_URL}/storage/v1/object/sign/driver-docs`, {
    method: 'POST',
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ expiresIn: 300, paths }),
  });
  if (!signRes.ok) {
    return new Response(JSON.stringify({ error: 'sign_failed' }), { status: 502 });
  }
  const signed: { path?: string; signedURL?: string; error?: string }[] = await signRes.json();
  const urls: Record<string, string | null> = {};
  for (const row of signed) {
    if (row.path && row.signedURL) urls[row.path] = `${SB_URL}/storage/v1${row.signedURL}`;
  }
  return new Response(JSON.stringify({ urls }), { status: 200, headers: { 'Content-Type': 'application/json' } });
};
