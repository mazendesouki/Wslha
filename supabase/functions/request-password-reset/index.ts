// =====================================================================
//  وصّلها — Edge Function: request-password-reset
//  Generates a 6-digit code SERVER-SIDE, stores it in `otps`, and emails it
//  to the account's registered address via Resend. The code is NEVER returned
//  to the browser — this closes the "code shown on screen" takeover hole.
//
//  Deploy:   supabase functions deploy request-password-reset --no-verify-jwt
//  Secrets:  supabase secrets set RESEND_API_KEY=re_xxx RESEND_FROM="وصّلها <noreply@yourdomain>"
//  (SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function localVariants(p: string): string[] {
  p = (p || '').trim().replace(/\s+/g, '');
  const set = new Set<string>();
  if (p) set.add(p);
  if (p.startsWith('+20')) set.add('0' + p.slice(3));
  if (p.startsWith('01'))  set.add('+2' + p);
  return [...set];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { phone } = await req.json();
    if (!phone) return json({ error: 'bad_request' }, 400);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Find the account (any stored phone format) and its email.
    const variants = localVariants(phone);
    const { data: rows } = await admin
      .from('accounts').select('phone,email,name')
      .in('phone', variants).limit(1);
    const acc = rows?.[0];
    if (!acc)        return json({ error: 'not_found' }, 404);
    if (!acc.email)  return json({ error: 'no_email' }, 422);

    // Generate the code server-side and store it (consumed later by reset_password).
    const code = String(Math.floor(100000 + Math.random() * 900000));
    await admin.from('otps').delete().eq('phone', acc.phone);
    const { error: insErr } = await admin.from('otps').insert({ phone: acc.phone, code });
    if (insErr) return json({ error: 'store_failed' }, 500);

    // Send the email via Resend.
    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    const RESEND_FROM = Deno.env.get('RESEND_FROM') || 'وصّلها <onboarding@resend.dev>';
    if (!RESEND_API_KEY) return json({ error: 'email_not_configured' }, 500);

    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [acc.email],
        subject: 'رمز استعادة كلمة المرور — وصّلها',
        html: `
          <div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;max-width:480px;margin:auto;padding:24px;background:#f8fafc;border-radius:12px">
            <h2 style="color:#1a2340;margin:0 0 8px">وصّلها</h2>
            <p style="color:#334155;font-size:15px">مرحباً ${acc.name || ''}،</p>
            <p style="color:#334155;font-size:15px">رمز استعادة كلمة المرور الخاص بك هو:</p>
            <div style="font-size:34px;font-weight:900;letter-spacing:10px;color:#1d4ed8;text-align:center;background:#fff;border:2px dashed #93c5fd;border-radius:10px;padding:16px;margin:16px 0">${code}</div>
            <p style="color:#64748b;font-size:13px">الرمز صالح لمدة 5 دقائق. إذا لم تطلب ذلك، تجاهل هذه الرسالة.</p>
          </div>`,
      }),
    });
    if (!emailRes.ok) {
      const detail = await emailRes.text().catch(() => '');
      console.error('Resend error:', emailRes.status, detail);
      return json({ error: 'email_send_failed' }, 502);
    }

    return json({ ok: true });
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
