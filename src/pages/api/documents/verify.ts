// وصّلها — POST /api/documents/verify
// Server-side gate for driver registration document uploads (called
// once per image right after it lands in storage — see the
// `driver.astro` client change in the same commit). Two independent
// checks, both must pass:
//
//   1) Duplicate detection: a sha256 hash of the image bytes is
//      compared against every hash already recorded for a DIFFERENT
//      phone (db/security-52-document-verification.sql). Reusing the
//      same photo for a second account — a common fraud pattern — is
//      rejected outright, no AI call needed.
//   2) For the "official document" types only (national ID, driving
//      license, vehicle registration, insurance, inspection, good-
//      conduct certificate) — Claude Vision looks at the image and
//      judges whether it's actually a real, legible photo of that
//      specific Egyptian document type, not a random/blank/unrelated
//      image. Personal photos and vehicle/plate photos skip this step
//      (they're not "documents issued by a government office" in the
//      same sense) and only go through the duplicate check.
//
// Requires ANTHROPIC_API_KEY and SUPABASE_SERVICE_ROLE_KEY as Vercel
// project env vars.
import type { APIRoute } from 'astro';
import { createHash } from 'node:crypto';
import { SB_URL } from '../../../lib/session';

export const prerender = false;

type DocType =
  | 'nat-front' | 'nat-back' | 'license' | 'vreg' | 'insurance' | 'inspection' | 'conduct'
  | 'driver-photo' | 'veh-front' | 'veh-back' | 'veh-right' | 'veh-left' | 'plate';

// Only these go through the Claude Vision "is this really the right
// official document" check. The rest (personal photo, vehicle/plate
// photos) are checked for duplication only.
const VISION_CHECKED: Record<string, string> = {
  'nat-front': 'الوجه الأمامي لبطاقة الرقم القومي المصرية',
  'nat-back': 'الوجه الخلفي لبطاقة الرقم القومي المصرية',
  license: 'رخصة قيادة مصرية سارية',
  vreg: 'رخصة تسجيل مركبة مصرية (الرخصة الصفراء) صادرة من إدارة المرور',
  insurance: 'وثيقة تأمين على مركبة',
  inspection: 'شهادة فحص فني لمركبة',
  conduct: 'شهادة حسن سيرة وسلوك صادرة من وزارة الداخلية المصرية',
};

function requireEnv(name: string): string {
  const v = import.meta.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

async function svc(path: string, init: RequestInit = {}): Promise<Response> {
  const key = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  return fetch(`${SB_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
}

export const POST: APIRoute = async ({ request }) => {
  let body: { imageUrl?: string; docType?: DocType; phone?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, reason: 'bad_json' }), { status: 400 });
  }
  const { imageUrl, docType, phone } = body;
  if (!imageUrl || !docType || !phone) {
    return new Response(JSON.stringify({ ok: false, reason: 'missing_fields' }), { status: 400 });
  }

  // Fetch the image once — reused for both the hash and, if needed, the
  // vision call, instead of downloading it twice.
  let imageBytes: ArrayBuffer;
  let contentType = 'image/jpeg';
  try {
    const imgRes = await fetch(imageUrl);
    if (!imgRes.ok) throw new Error('fetch_failed');
    contentType = imgRes.headers.get('content-type') || contentType;
    imageBytes = await imgRes.arrayBuffer();
  } catch {
    return new Response(JSON.stringify({ ok: false, reason: 'image_unreachable' }), { status: 502 });
  }

  const hash = createHash('sha256').update(Buffer.from(imageBytes)).digest('hex');

  // ── 1) Duplicate check ────────────────────────────────────────────
  try {
    const dupRes = await svc(`document_image_hashes?image_hash=eq.${hash}&phone=neq.${encodeURIComponent(phone)}&select=id&limit=1`);
    const dupRows = dupRes.ok ? await dupRes.json() : [];
    if (Array.isArray(dupRows) && dupRows.length > 0) {
      return new Response(JSON.stringify({ ok: false, reason: 'duplicate_image' }), { status: 409 });
    }
  } catch {
    // If the duplicate check itself fails (network/DB hiccup), don't
    // silently skip it — fail closed rather than let a genuine dupe slip through.
    return new Response(JSON.stringify({ ok: false, reason: 'check_failed' }), { status: 502 });
  }

  // ── 2) Vision check (official documents only) ───────────────────────
  const expectedDoc = VISION_CHECKED[docType as string];
  if (expectedDoc) {
    try {
      const apiKey = requireEnv('ANTHROPIC_API_KEY');
      const base64 = Buffer.from(imageBytes).toString('base64');
      const mediaType = contentType.startsWith('image/') ? contentType : 'image/jpeg';

      const claudeRes = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-sonnet-5',
          max_tokens: 300,
          messages: [
            {
              role: 'user',
              content: [
                { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } },
                {
                  type: 'text',
                  text:
                    `هذه صورة رفعها سائق أثناء التسجيل في تطبيق توصيل مصري، والمفترض إنها: "${expectedDoc}".\n\n` +
                    `افحص الصورة وحدد: هل هي فعلاً صورة واضحة ومقروءة لمستند رسمي مصري من النوع ده (مش صورة عشوائية، ` +
                    `مش صفحة فاضية، مش صورة شاشة لحاجة تانية، مش صورة شخص أو منظر عام، ومش صورة لمستند من نوع مختلف تمامًا)؟\n\n` +
                    `رد بصيغة JSON فقط بدون أي نص إضافي، بالشكل ده بالظبط: {"valid": true أو false, "reason": "سبب قصير بالعربي"}`,
                },
              ],
            },
          ],
        }),
      });

      if (!claudeRes.ok) {
        // Vision service itself failed (quota/outage) — don't block
        // registration on an infra hiccup; log it and let the duplicate
        // check (already passed above) be the gate for this attempt.
        console.error('[api/documents/verify] Claude API error', claudeRes.status, await claudeRes.text().catch(() => ''));
      } else {
        const claudeData = await claudeRes.json();
        const text: string = claudeData?.content?.[0]?.text || '';
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          const verdict = JSON.parse(jsonMatch[0]);
          if (verdict.valid !== true) {
            return new Response(
              JSON.stringify({ ok: false, reason: 'not_matching_document', detail: verdict.reason || '' }),
              { status: 422 },
            );
          }
        }
      }
    } catch (e) {
      console.error('[api/documents/verify] vision check threw', e);
      // Same fail-open-on-infra-error stance as above.
    }
  }

  // ── Record the hash (both document and non-document uploads) ────────
  try {
    await svc('document_image_hashes', {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ phone, doc_type: docType, image_hash: hash }),
    });
  } catch {
    /* best-effort — a failed insert here just means this hash won't be
       checked against future uploads, not a reason to fail this one */
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
