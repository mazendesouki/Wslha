// وصّلها — دالة إرسال الحملات التسويقية عبر البريد
// تُستدعى من send_due_email_campaigns() (db/security-100/101/102) بنفس
// نمط التحقق بتاع send-push بالضبط (x-push-secret).
//
// image_url (security-101) — بانر إعلاني اختياري.
// extra_emails (security-102) — قائمة بريد إضافية اختيارية (مش لازم حسابات
// مسجّلة بالتطبيق) — لإعلانات البراند لجهات خارجية/قوائم مجمّعة، تُدمج
// مع إيميلات الفئة المستهدفة ويُزال منها المكرر.
//
// تحذير مهم: دومين جديد لسة أيام (وصّلها اتفعّل للإرسال منذ  2026-09-25)
// يحتاج تدرج بطيء في الحجم — إرسال دفعة واحدة لكل المستخدمين من
// دومين عمره يوم واحد علامة مشبوهة قوية لأنظمة مكافحة Gmail، وممكن
// يضر السمعة بدل ما يحسّنها — الأدمن يختار فئة مستهدفة أصغر
// (مثلاً role معين بدل 'all') لحد من الحجم في الأيام الأولى.
//
// Footer (2026-09-26): real brand contact info (same numbers/links
// Footer.astro uses) + a CSS-only logo mark — no actual logo IMAGE,
// since Gmail doesn't render data: URI images and there's no hosted
// logo asset to link to; a colored badge with an emoji is the safest
// cross-client stand-in.
import { createClient } from 'npm:@supabase/supabase-js@2';

const TRIGGER_SECRET = Deno.env.get('PUSH_TRIGGER_SECRET')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;
const RESEND_FROM = Deno.env.get('RESEND_FROM') || 'وصّلها <accounts@wslha.co>';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Same teal-header/gold-accent brand shell as swift-processor's OTP
// email (public/global.css tokens) — generic paragraph body instead of
// a code box, plus an optional banner image right under the header.
function brandEmailHtml(subject: string, bodyText: string, imageUrl?: string | null): string {
  const paragraphs = bodyText
    .split('\n')
    .filter((p) => p.trim().length > 0)
    .map((p) => `<p style="color:#16262A;font-size:14px;margin:0 0 14px;line-height:1.8">${escapeHtml(p)}</p>`)
    .join('');
  const imageBlock = imageUrl
    ? `<tr><td style="padding:0"><img src="${imageUrl}" width="100%" alt="" style="display:block;width:100%;height:auto"/></td></tr>`
    : '';
  return `
<div style="background:#F2F7F6;padding:32px 16px;font-family:Tahoma,Arial,sans-serif">
  <table role="presentation" width="100%" style="max-width:480px;margin:0 auto;border-collapse:collapse" dir="rtl">
    <tr>
      <td style="background:#0E4B49;border-radius:14px 14px 0 0;padding:28px 24px;text-align:center">
        <div style="color:#ffffff;font-size:22px;font-weight:900">وصّلها</div>
        <div style="color:rgba(255,255,255,0.7);font-size:11px;margin-top:2px">خدمة توصيل دمياط</div>
      </td>
    </tr>
    ${imageBlock}
    <tr>
      <td style="background:#ffffff;border:1px solid #E2E8F0;border-top:none;border-radius:0 0 14px 14px;padding:28px 24px">
        <h2 style="color:#0E4B49;font-size:17px;margin:0 0 14px">${escapeHtml(subject)}</h2>
        ${paragraphs}
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
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
  if (req.headers.get('x-push-secret') !== TRIGGER_SECRET) {
    return new Response('forbidden', { status: 403 });
  }

  let payload: { target?: string; subject?: string; body?: string; image_url?: string | null; extra_emails?: string[] | null };
  try { payload = await req.json(); } catch { return new Response('bad json', { status: 400 }); }

  const subject = payload.subject || 'وصّلها';
  const bodyText = payload.body || '';
  const role = payload.target || 'customer';

  let query = admin.from('accounts').select('email').not('email', 'is', null);
  query = role === 'all' ? query.in('role', ['customer', 'driver', 'merchant']) : query.eq('role', role);
  const { data: rows, error } = await query;
  if (error) return new Response('db error: ' + error.message, { status: 500 });

  const roleEmails = (rows || []).map((r) => r.email as string).filter(Boolean);
  // Defensive: re-split each entry on whitespace too, in case the caller
  // joined multiple addresses with a space instead of a comma/newline —
  // that silently dropped a whole entry before (a combined "a@x.com
  // b@y.com" string fails EMAIL_RE outright, since it isn't one address).
  const extraEmails = (payload.extra_emails || [])
    .flatMap((e) => (typeof e === 'string' ? e.split(/\s+/) : []))
    .map((e) => e.trim())
    .filter((e) => EMAIL_RE.test(e));
  const emails = [...new Set([...roleEmails, ...extraEmails])];
  if (!emails.length) return Response.json({ sent: 0, total: 0 });

  const html = brandEmailHtml(subject, bodyText, payload.image_url);
  let sent = 0;

  // Resend's batch endpoint accepts up to 100 emails per call.
  for (let i = 0; i < emails.length; i += 100) {
    const chunk = emails.slice(i, i + 100);
    const res = await fetch('https://api.resend.com/emails/batch', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(chunk.map((to) => ({ from: RESEND_FROM, to: [to], subject, html }))),
    });
    if (res.ok) sent += chunk.length;
    else console.error('[send-marketing-email] resend batch failed', res.status, await res.text().catch(() => ''));
  }

  return Response.json({ sent, total: emails.length });
});
