// =====================================================================
//  وصّلها — Edge Function: request-password-reset
//  Generates a 6-digit code SERVER-SIDE, stores it in `otps`, and emails it
//  to the account's registered address via Resend. The code is NEVER returned
//  to the browser — this closes the "code shown on screen" takeover hole.
//
//  Deploy:   supabase functions deploy request-password-reset --no-verify-jwt
//  Secrets:  supabase secrets set RESEND_API_KEY=re_xxx RESEND_FROM="وصّلها <noreply@yourdomain>"
//  (SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
//
//  wslha.co is verified on Resend (2026-09-25). Sender switched from
//  noreply@ to accounts@wslha.co (2026-09-26) — Resend's deliverability
//  insights flag "no-reply" as hurting inbox placement. Email template
//  (2026-09-26) rebuilt to match the site's real brand tokens (public/
//  global.css): teal #0E4B49 header, gold #B8863B accent on the code box
//  — previously just a generic blue box with no brand identity at all.
//  Still overridable via the RESEND_FROM secret if that's ever set.
//
//  Footer (2026-09-26): real brand contact info (same numbers/links
//  Footer.astro uses) + a CSS-only logo mark — no actual logo IMAGE,
//  since Gmail doesn't render data: URI images and there's no hosted
//  logo asset to link to; a colored badge with an emoji is the safest
//  cross-client stand-in.
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

// Table-based layout with every style inlined — the only markup pattern
// that renders consistently across Gmail/Outlook/Apple Mail (flexbox/grid
// and <style> blocks are unreliable in email clients). Colors/radii/fonts
// pulled straight from public/global.css's :root tokens.
function otpEmailHtml(name: string, code: string): string {
  return `
<div style="background:#F2F7F6;padding:32px 16px;font-family:Tahoma,Arial,sans-serif">
  <table role="presentation" width="100%" style="max-width:480px;margin:0 auto;border-collapse:collapse" dir="rtl">
    <tr>
      <td style="background:#0E4B49;border-radius:14px 14px 0 0;padding:28px 24px;text-align:center">
        <div style="display:inline-block;width:44px;height:44px;background:rgba(255,255,255,0.15);border-radius:12px;color:#ffffff;font-size:22px;line-height:44px;margin-bottom:10px">🚚</div>
        <div style="color:#ffffff;font-size:22px;font-weight:900">وصّلها</div>
        <div style="color:rgba(255,255,255,0.7);font-size:11px;margin-top:2px">خدمة توصيل دمياط</div>
      </td>
    </tr>
    <tr>
      <td style="background:#ffffff;border:1px solid #E2E8F0;border-top:none;border-radius:0 0 14px 14px;padding:28px 24px">
        <p style="color:#16262A;font-size:15px;margin:0 0 6px">مرحباً ${name}،</p>
        <p style="color:#5B6B6A;font-size:14px;margin:0 0 18px;line-height:1.6">رمز استعادة كلمة المرور الخاص بك هو:</p>
        <div style="font-size:32px;font-weight:900;letter-spacing:8px;color:#96692A;text-align:center;background:#F8FAFC;border:2px dashed #B8863B;border-radius:10px;padding:16px;margin-bottom:18px">${code}</div>
        <p style="color:#8A9998;font-size:12px;margin:0;line-height:1.6">الرمز صالح لمدة 5 دقائق. إذا لم تطلب ذلك، تجاهل هذه الرسالة.</p>
      </td>
    </tr>
    <tr>
      <td style="text-align:center;padding:22px 16px 4px">
        <div style="margin-bottom:8px">
          <span style="display:inline-block;width:24px;height:24px;background:#0E4B49;border-radius:7px;color:#ffffff;font-size:12px;line-height:24px;vertical-align:middle;margin-inline-end:6px">🚚</span>
          <span style="font-size:14px;font-weight:900;color:#0E4B49;vertical-align:middle">وصّلها</span>
        </div>
        <p style="color:#8A9998;font-size:11px;margin:0 0 10px;line-height:1.7">خدمة توصيل سريعة وموثوقة — مشاوير، توصيل مطار، طلبات من المتاجر، وطرود.</p>
        <p style="margin:0 0 10px;font-size:11px">
          <a href="tel:+201102667324" style="color:#0E4B49;text-decoration:none;font-weight:700">📞 0020 1102 667324</a>
          &nbsp;·&nbsp;
          <a href="mailto:info@wslha.co" style="color:#0E4B49;text-decoration:none;font-weight:700">✉️ info@wslha.co</a>
          &nbsp;·&nbsp;
          <a href="https://wa.me/201102667324" style="color:#0E4B49;text-decoration:none;font-weight:700">💬 واتساب</a>
        </p>
        <p style="color:#B7C4C3;font-size:10px;margin:0">© 2024–2026 وصّلها · wslha.co · جميع الحقوق محفوظة</p>
      </td>
    </tr>
  </table>
</div>`;
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
    const RESEND_FROM = Deno.env.get('RESEND_FROM') || 'وصّلها <accounts@wslha.co>';
    if (!RESEND_API_KEY) return json({ error: 'email_not_configured' }, 500);

    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [acc.email],
        subject: 'رمز استعادة كلمة المرور — وصّلها',
        html: otpEmailHtml(acc.name || '', code),
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
