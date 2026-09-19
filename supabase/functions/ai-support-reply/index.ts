// =====================================================================
//  وصّلها — Edge Function: ai-support-reply
//  Generates the automatic support-chat reply using Claude (Anthropic).
//  The API key never reaches the app or the database — it's a server-side
//  secret on this function only.
//
//  Called by the client right after send_support_message() succeeds
//  (support_chat_repository.dart). Verifies the conversation belongs to
//  the given phone, skips silently once a human admin has taken over
//  (support_conversations.ai_enabled = false — set by
//  admin_send_support_reply) or once the feature flag is off.
//
//  Deploy:   supabase functions deploy ai-support-reply --no-verify-jwt
//  Secrets:  supabase secrets set ANTHROPIC_API_KEY=...
//  (SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
// =====================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SYSTEM_PROMPT = `انت مساعد الدعم الفني لتطبيق "وصّلها" — تطبيق مصري لطلب الرحلات والتوصيل (زي أوبر/كريم بس لمصر).
جاوب بالعربي المصري العامي، بأسلوب ودود ومختصر (جملتين-تلاتة بالكتير).
لو السؤال محتاج تدخل بشري فعلي (شكوى، استرجاع فلوس، مشكلة أمان) قول للعميل إن فريق الدعم هيتابع معاه بنفسه.
ماتخترعش معلومات عن أسعار أو سياسات مش متأكد منها — لو مش عارف، قول هتحول الموضوع لفريق الدعم البشري.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { conversation_id, phone } = await req.json();
    if (!conversation_id || !phone) return json({ error: 'bad_request' }, 400);

    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');
    if (!ANTHROPIC_API_KEY) return json({ error: 'bot_not_configured' }, 500);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: conv } = await admin
      .from('support_conversations')
      .select('id, user_phone, ai_enabled')
      .eq('id', conversation_id)
      .single();
    // Ownership check mirrors every other RPC in this project — a phone
    // that doesn't own this conversation gets nothing back.
    if (!conv || conv.user_phone !== phone) return json({ error: 'not_found' }, 404);
    if (!conv.ai_enabled) return json({ ok: true, skipped: 'human_active' });

    const { data: flag } = await admin.from('app_settings').select('value').eq('key', 'feature_ai_bot_enabled').maybeSingle();
    if (flag && flag.value !== 'true') return json({ ok: true, skipped: 'flag_off' });

    const { data: history } = await admin
      .from('support_messages')
      .select('sender_role, body')
      .eq('conversation_id', conversation_id)
      .order('created_at', { ascending: true })
      .limit(20);

    const messages = (history || [])
      .filter((m) => m.sender_role !== 'support') // a human already took over — see ai_enabled check above
      .map((m) => ({ role: m.sender_role === 'ai' ? 'assistant' : 'user', body: m.body }));
    if (!messages.length) return json({ ok: true, skipped: 'no_messages' });

    const claudeRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 300,
        system: SYSTEM_PROMPT,
        messages: messages.map((m) => ({ role: m.role, content: m.body })),
      }),
    });

    if (!claudeRes.ok) {
      const detail = await claudeRes.text().catch(() => '');
      console.error('Anthropic error:', claudeRes.status, detail);
      return json({ error: 'ai_error' }, 502);
    }

    const claudeJson = await claudeRes.json();
    const reply = claudeJson?.content?.[0]?.text?.trim();
    if (!reply) return json({ error: 'ai_empty' }, 502);

    await admin.from('support_messages').insert({
      conversation_id, sender_role: 'ai', body: reply, read_by_admin: true,
    });
    await admin.from('support_conversations').update({ updated_at: new Date().toISOString() }).eq('id', conversation_id);

    return json({ ok: true, reply });
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
