// وصّلها — Dispatch Engine
// محرك مطابقة/توزيع منفصل يشتغل جنب Supabase (مش بديل عنه): بيراقب
// الرحلات والطلبات الجديدة، ويعرضها على أقرب سائق متاح "واحد في المرة"
// بدل بثّها لكل السائقين المتصلين مرة واحدة. لو السائق رفض أو محتردش
// خلال 30 ثانية، الطلب يتحول تلقائياً لأقرب سائق تاني.
//
// لو السيرفر ده واقف أو مفيش سائقين قريبين، شاشة السائق (driver-dashboard)
// عندها fallback بثّي قديم بيشتغل تلقائياً بعد مهلة — النظام مايقفش.
import express from 'express';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL   = process.env.SUPABASE_URL;
const SERVICE_KEY    = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PUSH_URL        = process.env.PUSH_FUNCTION_URL;   // e.g. https://<project>.supabase.co/functions/v1/send-push
const PUSH_SECRET     = process.env.PUSH_TRIGGER_SECRET;
const PORT            = process.env.PORT || 3000;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('[dispatch] Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars — exiting.');
  process.exit(1);
}

const OFFER_TIMEOUT_MS  = 30_000; // driver has 30s to respond to an offer
const POLL_MS           = 2_000;  // how often we check whether an offer was answered
const DRIVER_FRESH_MS   = 3 * 60 * 1000; // ignore GPS pings older than this (driver likely disconnected)
const SWEEP_INTERVAL_MS = 15_000; // periodic catch-up sweep (covers missed realtime events / restarts)

const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

// target keys ("ride:123") currently being dispatched — prevents double-dispatch
// from an overlapping realtime event + sweep tick.
const inFlight = new Set();

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function nearestAvailableDrivers(lat, lng) {
  if (typeof lat !== 'number' || typeof lng !== 'number') return [];
  const since = new Date(Date.now() - DRIVER_FRESH_MS).toISOString();
  const { data, error } = await db
    .from('driver_locations')
    .select('driver_phone, driver_name, lat, lng')
    .eq('is_online', true)
    .is('ride_id', null)
    .is('current_order_id', null)
    .gte('updated_at', since);
  if (error || !data) return [];
  return data
    .filter(d => typeof d.lat === 'number' && typeof d.lng === 'number')
    .map(d => ({ ...d, distanceKm: haversineKm(lat, lng, d.lat, d.lng) }))
    .sort((a, b) => a.distanceKm - b.distanceKm);
}

async function sendPushToDriver(phone, title, body, url) {
  if (!PUSH_URL || !PUSH_SECRET) return;
  try {
    await fetch(PUSH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-push-secret': PUSH_SECRET },
      body: JSON.stringify({ phone, title, body, url }),
    });
  } catch (e) {
    console.error('[dispatch] push failed', e.message);
  }
}

async function isStillUnclaimed(type, id) {
  const table = type === 'ride' ? 'rides' : 'orders';
  const { data } = await db.from(table).select('driver_phone').eq('id', id).limit(1).maybeSingle();
  return !!data && !data.driver_phone;
}

async function waitForOfferResolution(offerId) {
  const deadline = Date.now() + OFFER_TIMEOUT_MS + 1000;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, POLL_MS));
    const { data } = await db.from('dispatch_offers').select('status').eq('id', offerId).maybeSingle();
    if (data?.status === 'accepted') return true;
    if (data?.status === 'rejected') return false;
  }
  await db.from('dispatch_offers').update({ status: 'expired' }).eq('id', offerId).eq('status', 'pending');
  return false;
}

async function dispatchTarget(type, id, lat, lng, label) {
  const key = `${type}:${id}`;
  if (inFlight.has(key)) return;
  inFlight.add(key);
  try {
    if (!(await isStillUnclaimed(type, id))) return;
    const candidates = await nearestAvailableDrivers(lat, lng);
    if (!candidates.length) {
      console.log(`[dispatch] no available drivers for ${key} — leaving for broadcast fallback`);
      return;
    }

    for (const d of candidates) {
      if (!(await isStillUnclaimed(type, id))) return;

      const offerId = `off-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      const expiresAt = new Date(Date.now() + OFFER_TIMEOUT_MS).toISOString();
      const { error: insErr } = await db.from('dispatch_offers').insert({
        id: offerId, target_type: type, target_id: id,
        driver_phone: d.driver_phone, status: 'pending', expires_at: expiresAt,
      });
      if (insErr) { console.error('[dispatch] offer insert failed', insErr.message); continue; }

      await sendPushToDriver(d.driver_phone, label.title, label.body, label.url);
      console.log(`[dispatch] offered ${key} to ${d.driver_phone} (${d.distanceKm.toFixed(1)}km)`);

      const accepted = await waitForOfferResolution(offerId);
      if (accepted) { console.log(`[dispatch] ${key} accepted by ${d.driver_phone}`); return; }
      if (!(await isStillUnclaimed(type, id))) return; // claimed via legacy fallback meanwhile
    }
    console.log(`[dispatch] exhausted nearby candidates for ${key} — leaving for broadcast fallback`);
  } finally {
    inFlight.delete(key);
  }
}

// ── Realtime: react immediately to new pending rides ──
db.channel('dispatch-new-rides')
  .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'rides' }, ({ new: ride }) => {
    if (ride.status === 'pending' && !ride.driver_phone) {
      dispatchTarget('ride', ride.id, ride.from_lat, ride.from_lng, {
        title: '🚗 طلب رحلة جديد!',
        body: `${ride.from_area || ''} ← ${ride.to_area || ''} — ${ride.fare || ''} ج.م`,
        url: '/driver-dashboard',
      });
    }
  })
  .subscribe();

// ── Realtime: react when a merchant marks an order ready for pickup ──
db.channel('dispatch-new-orders')
  .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'orders' }, ({ new: order }) => {
    if (order.status === 'preparing' && !order.driver_phone) {
      dispatchTarget('order', order.id, order.store_lat, order.store_lng, {
        title: '🛵 طلب توصيل جديد!',
        body: `من ${order.store_name || order.store_id || ''}`,
        url: '/driver-dashboard',
      });
    }
  })
  .subscribe();

// ── Sweep: catches anything the realtime channel missed (dropped
//    connection, server restart mid-dispatch, etc). ──
async function sweep() {
  try {
    const { data: rides } = await db.from('rides')
      .select('id, from_lat, from_lng, from_area, to_area, fare')
      .eq('status', 'pending').is('driver_phone', null);
    for (const r of rides || []) {
      dispatchTarget('ride', r.id, r.from_lat, r.from_lng, {
        title: '🚗 طلب رحلة جديد!',
        body: `${r.from_area || ''} ← ${r.to_area || ''} — ${r.fare || ''} ج.م`,
        url: '/driver-dashboard',
      });
    }
    const { data: orders } = await db.from('orders')
      .select('id, store_lat, store_lng, store_name, store_id')
      .eq('status', 'preparing').is('driver_phone', null);
    for (const o of orders || []) {
      dispatchTarget('order', o.id, o.store_lat, o.store_lng, {
        title: '🛵 طلب توصيل جديد!',
        body: `من ${o.store_name || o.store_id || ''}`,
        url: '/driver-dashboard',
      });
    }
  } catch (e) {
    console.error('[sweep] error', e.message);
  }
}
setInterval(sweep, SWEEP_INTERVAL_MS);
sweep();

// ── Health check — also the target for an external keep-alive ping
//    (free hosts like Render sleep an idle web service; a cron ping
//    every ~10 min keeps this process, and its realtime connection, alive). ──
const app = express();
app.get('/health', (_req, res) => {
  res.json({ ok: true, inFlight: inFlight.size, time: new Date().toISOString() });
});
app.listen(PORT, () => console.log(`[dispatch] listening on :${PORT}`));
