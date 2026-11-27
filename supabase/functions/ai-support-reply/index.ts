// =====================================================================
//  وصّلها — Edge Function: ai-support-reply
//  Generates the automatic support-chat reply using Claude (Anthropic).
//  The API key never reaches the app or the database — it's a server-side
//  secret on this function only.
//
//  Streams the reply (db/security-194): inserts an empty placeholder row
//  immediately and updates its `body` as tokens arrive from Anthropic's
//  SSE stream, throttled to ~4/sec — the client watches this row live via
//  Supabase Realtime (support_messages is in the realtime publication
//  with a permissive SELECT policy, same pattern as rides/driver_locations/
//  dispatch_offers) instead of waiting for the existing 10s poll to catch
//  the finished reply. `streaming` flips to false on the row's final
//  update, which is also the client's signal that the reply is complete.
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

// Minimum gap between row updates while streaming — Anthropic can emit
// dozens of small text deltas per second; updating on every single one
// would mean dozens of Postgres writes (and realtime broadcasts) per
// reply for no visible benefit over a smooth ~4-per-second reveal.
const MIN_UPDATE_INTERVAL_MS = 250;

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
        stream: true,
      }),
    });

    if (!claudeRes.ok || !claudeRes.body) {
      const detail = await claudeRes.text().catch(() => '');
      console.error('Anthropic error:', claudeRes.status, detail);
      return json({ error: 'ai_error' }, 502);
    }

    // Placeholder row the client watches live — inserted before the first
    // token so the chat shows a reply "typing in" immediately rather than
    // only once Claude has finished.
    const { data: placeholder, error: insertErr } = await admin
      .from('support_messages')
      .insert({ conversation_id, sender_role: 'ai', body: '', read_by_admin: true, streaming: true })
      .select('id')
      .single();
    if (insertErr || !placeholder) {
      console.error('placeholder insert failed:', insertErr);
      return json({ error: 'server_error' }, 500);
    }
    const messageId = placeholder.id;

    let reply = '';
    let lastUpdateAt = 0;
    try {
      const reader = claudeRes.body.getReader();
      const decoder = new TextDecoder();
      let buf = '';
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split('\n');
        buf = lines.pop() ?? ''; // keep the last, possibly-incomplete line for next read
        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          let evt: unknown;
          try {
            evt = JSON.parse(line.slice('data: '.length));
          } catch {
            continue;
          }
          const e = evt as { type?: string; delta?: { type?: string; text?: string } };
          if (e.type === 'content_block_delta' && e.delta?.type === 'text_delta' && e.delta.text) {
            reply += e.delta.text;
            const now = Date.now();
            if (now - lastUpdateAt >= MIN_UPDATE_INTERVAL_MS) {
              lastUpdateAt = now;
              await admin.from('support_messages').update({ body: reply }).eq('id', messageId);
            }
          }
        }
      }
    } catch (streamErr) {
      console.error('stream read error:', streamErr);
      // Fall through with whatever text arrived before the stream broke —
      // finalizing below still clears `streaming` so the client never
      // waits forever on a dropped connection.
    }

    reply = reply.trim();
    if (!reply) {
      // Nothing usable came through — remove the empty placeholder rather
      // than leaving a blank "AI" bubble in the conversation.
      await admin.from('support_messages').delete().eq('id', messageId);
      return json({ error: 'ai_empty' }, 502);
    }

    await admin.from('support_messages').update({ body: reply, streaming: false }).eq('id', messageId);
    await admin.from('support_conversations').update({ updated_at: new Date().toISOString() }).eq('id', conversation_id);

    // Best-effort — the customer is usually already looking at the chat
    // screen when the bot answers (it fires right after they send a
    // message), but push still matters if they've since backgrounded the
    // app while waiting. Mirrors admin_send_support_reply's push exactly.
    await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-push-secret': Deno.env.get('PUSH_TRIGGER_SECRET') ?? '',
        apikey: 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4',
      },
      body: JSON.stringify({
        phone,
        title: '🤖 رد المساعد الآلي',
        body: reply,
        url: '/support',
        tag: `wslha-support-reply-${conversation_id}`,
      }),
    }).catch(() => {});

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
