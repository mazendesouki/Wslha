// وصّلها — دالة إرسال الحملات التسويقية عبر البريد
// تُستدعى من send_due_email_campaigns() (db/security-100/101) بنفس
// نمط التحقق بتاع send-push بالضبط (x-push-secret) — امتداد
// لأداة الإشعارات الترويجية الموجودة لتشمل قناة البريد كمان
// طلب صراحة (لبناء سمعة الدومين الجديد عند Gmail بإرسال حقيقي
// مرغوب فيه، مش بس اختبار).
//
// image_url (security-101) — بانر إعلاني اختياري أفقي يظهر تحت الهيدر
// التيلي مباشرة لحملات أكثر احترافية/تسويقية — نفس المقاس الموصى به (1080×566)
// ونفس bucket 'promotions' المستخدم في أداة النوافذ المنبثقة (security-98b).
//
// تحذير مهم: دومين جديد لسة أيام (وصّلها اتفعّل للإرسال منذ  2026-09-25)
// يحتاج تدرج بطيء في الحجم — إرسال دفعة واحدة لكل المستخدمين من
// دومين عمره يوم واحد علامة مشبوهة قوية لأنظمة مكافحة Gmail، وممكن
// يضر السمعة بدل ما يحسّنها — الأدمن يختار فئة مستهدفة أصغر
// (مثلاً role معين بدل 'all') لحد من الحجم في الأيام الأولى.
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
      <td style="text-align:center;padding:16px 0;color:#8A9998;font-size:11px">وصّلها — خدمة توصيل دمياط</td>
    </tr>
  </table>
</div>`;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
  if (req.headers.get('x-push-secret') !== TRIGGER_SECRET) {
    return new Response('forbidden', { status: 403 });
  }

  let payload: { target?: string; subject?: string; body?: string; image_url?: string | null };
  try { payload = await req.json(); } catch { return new Response('bad json', { status: 400 }); }

  const subject = payload.subject || 'وصّلها';
  const bodyText = payload.body || '';
  const role = payload.target || 'customer';

  let query = admin.from('accounts').select('email').not('email', 'is', null);
  query = role === 'all' ? query.in('role', ['customer', 'driver', 'merchant']) : query.eq('role', role);
  const { data: rows, error } = await query;
  if (error) return new Response('db error: ' + error.message, { status: 500 });

  const emails = [...new Set((rows || []).map((r) => r.email as string).filter(Boolean))];
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
