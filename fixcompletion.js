#!/usr/bin/env node
/**
 * Fixes for: activity log, stats, spending total, ride/order completion flow
 * Run from E:\Wslha: node fixcompletion.js
 */
const fs = require('fs');
const path = require('path');

let totalChanged = 0;

function patch(relPath, fixes) {
  const file = path.join(__dirname, relPath);
  let src = fs.readFileSync(file, 'utf8');
  let fileChanged = 0;
  for (const [old, neo, label] of fixes) {
    if (src.includes(neo)) { console.log(`  ✅ already applied: ${label}`); continue; }
    if (!src.includes(old)) { console.error(`  ❌ pattern not found: ${label}`); continue; }
    src = src.replace(old, neo);
    fileChanged++;
    console.log(`  ✅ ${label}`);
  }
  if (fileChanged > 0) { fs.writeFileSync(file, src, 'utf8'); totalChanged += fileChanged; }
  return fileChanged;
}

// ─────────────────────────────────────────────────────────────
// 1. driver-dashboard.astro
// ─────────────────────────────────────────────────────────────
console.log('\n[1/4] driver-dashboard.astro');
patch('src/pages/driver-dashboard.astro', [

  // Fix: wallet balance overwrites instead of accumulating — use RPC
  [
    `      // Upsert driver wallet
      fetch(\`\${SB_URL}/rest/v1/wallets\`, {
        method: 'POST',
        headers: { ...SB_H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ phone, balance: driverEarn, updated_at: now }),
      }),`,
    `      // Add to driver wallet (accumulate, not overwrite)
      fetch(\`\${SB_URL}/rest/v1/rpc/add_wallet_balance\`, {
        method: 'POST',
        headers: SB_H,
        body: JSON.stringify({ p_phone: phone, p_amount: driverEarn }),
      }),`,
    'wallet: use add_wallet_balance RPC (accumulate)'
  ],

  // Fix: points total overwrites instead of accumulating — use RPC
  [
    `      // Upsert points total
      fetch(\`\${SB_URL}/rest/v1/points\`, {
        method: 'POST',
        headers: { ...SB_H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ phone, total_points: pointsEarned, updated_at: now }),
      }),`,
    `      // Add to points total (accumulate, not overwrite)
      fetch(\`\${SB_URL}/rest/v1/rpc/add_points\`, {
        method: 'POST',
        headers: SB_H,
        body: JSON.stringify({ p_phone: phone, p_amount: pointsEarned }),
      }),`,
    'points: use add_points RPC (accumulate)'
  ],

  // Fix: refresh activity log + credit merchant wallet after delivery completion
  [
    `      await recordCompletion('delivery', orderId, fee);
      currentOrder = null;`,
    `      await recordCompletion('delivery', orderId, fee);
      // Credit merchant wallet for this delivery
      try {
        const storeId = (currentOrder || {}).store_id;
        if (storeId) {
          const storeData = await fetch(\`\${SB_URL}/rest/v1/stores?id=eq.\${storeId}&select=owner_phone\`, { headers: SB_H }).then(r => r.json());
          const mPhone = storeData?.[0]?.owner_phone;
          if (mPhone) {
            const subtotal = Math.max(0, ((currentOrder || {}).total || 0) - fee);
            await Promise.allSettled([
              fetch(\`\${SB_URL}/rest/v1/rpc/add_wallet_balance\`, { method: 'POST', headers: SB_H, body: JSON.stringify({ p_phone: mPhone, p_amount: subtotal }) }),
              fetch(\`\${SB_URL}/rest/v1/wallet_transactions\`, { method: 'POST', headers: SB_H, body: JSON.stringify({ id: 'mtx-'+Date.now(), phone: mPhone, amount: subtotal, type: 'earning', reference_id: orderId, note: 'إيرادات طلب توصيل', created_at: new Date().toISOString() }) }),
            ]);
          }
        }
      } catch {}
      setTimeout(() => loadActivityLog(), 600);
      currentOrder = null;`,
    'delivery complete: credit merchant + refresh activity log'
  ],

  // Fix: refresh activity log after ride completion
  [
    `    await recordCompletion('ride', rideId, fare || 0);
    currentRide = null;`,
    `    await recordCompletion('ride', rideId, fare || 0);
    setTimeout(() => loadActivityLog(), 600);
    currentRide = null;`,
    'ride complete: refresh activity log'
  ],
]);

// ─────────────────────────────────────────────────────────────
// 2. rides.astro — update localStorage status on completion
// ─────────────────────────────────────────────────────────────
console.log('\n[2/4] rides.astro');
patch('src/pages/rides.astro', [
  [
    `    if (ride.status === 'completed') {
      stopPoller();
      advanceStatus('done');
      setTimeout(() => showRatingScreen(ride), 1800);
    }
    if (ride.status === 'cancelled') {
      stopPoller();
      resetToBooking();
    }`,
    `    if (ride.status === 'completed') {
      stopPoller();
      try {
        const _u = JSON.parse(localStorage.getItem('wslha_user') || '{}');
        const _k = _u.phone ? 'wslha_orders_' + _u.phone : 'wslha_orders';
        const _os = JSON.parse(localStorage.getItem(_k) || '[]');
        const _ix = _os.findIndex(o => o.id === activeRideId);
        if (_ix >= 0) { _os[_ix].status = 'completed'; localStorage.setItem(_k, JSON.stringify(_os)); }
      } catch {}
      advanceStatus('done');
      setTimeout(() => showRatingScreen(ride), 1800);
    }
    if (ride.status === 'cancelled') {
      stopPoller();
      try {
        const _u = JSON.parse(localStorage.getItem('wslha_user') || '{}');
        const _k = _u.phone ? 'wslha_orders_' + _u.phone : 'wslha_orders';
        const _os = JSON.parse(localStorage.getItem(_k) || '[]');
        const _ix = _os.findIndex(o => o.id === activeRideId);
        if (_ix >= 0) { _os[_ix].status = 'cancelled'; localStorage.setItem(_k, JSON.stringify(_os)); }
      } catch {}
      resetToBooking();
    }`,
    'localStorage status update on ride complete/cancel'
  ],
]);

// ─────────────────────────────────────────────────────────────
// 3. profile.astro — include rides fare in total spending
// ─────────────────────────────────────────────────────────────
console.log('\n[3/4] profile.astro');
patch('src/pages/profile.astro', [
  [
    `    const totalSpent = orders
      .filter(o => o.status === 'delivered' || o.status === 'completed')
      .reduce((s, o) => s + (Number(o.total) || 0), 0);

    $('stat-orders').textContent = orders.length;
    $('stat-spent').textContent  = fmt(Math.round(totalSpent)) + ' ج.م';
    $('stat-rides').textContent  = rides.length;
    $('stat-month').textContent  = thisMonth.length;`,
    `    const totalSpent =
      orders.filter(o => o.status === 'delivered' || o.status === 'completed')
            .reduce((s, o) => s + (Number(o.total) || 0), 0)
      + rides.filter(r => r.status === 'completed')
             .reduce((s, r) => s + (Number(r.fare) || 0), 0);

    $('stat-orders').textContent = orders.length;
    $('stat-spent').textContent  = fmt(Math.round(totalSpent)) + ' ج.م';
    $('stat-rides').textContent  = rides.length;
    $('stat-month').textContent  = thisMonth.length;`,
    'spending stat: include completed rides fare'
  ],
]);

// ─────────────────────────────────────────────────────────────
// 4. merchant-dashboard.astro — fix stats to count delivered only
// ─────────────────────────────────────────────────────────────
console.log('\n[4/4] merchant-dashboard.astro');
patch('src/pages/merchant-dashboard.astro', [
  [
    `      sbGet(\`orders?store_id=eq.\${currentStore.id}&created_at=gte.\${today}&select=total\`),`,
    `      sbGet(\`orders?store_id=eq.\${currentStore.id}&created_at=gte.\${today}&status=in.(delivered,completed)&select=total,subtotal\`),`,
    'stats: count only delivered/completed orders'
  ],
  [
    `    const todayRevenue = (todayOrd || []).reduce((s: number, o: any) => s + (o.total || 0), 0);`,
    `    const todayRevenue = (todayOrd || []).reduce((s: number, o: any) => s + (o.subtotal || o.total || 0), 0);`,
    'revenue: use subtotal (merchant take, excluding delivery fee)'
  ],
]);

console.log(`\n✅ Done — ${totalChanged} change(s) applied`);
if (totalChanged > 0) {
  console.log('\nNext steps:');
  console.log('  git add src/pages/driver-dashboard.astro src/pages/rides.astro src/pages/profile.astro src/pages/merchant-dashboard.astro');
  console.log('  git commit -m "Fix completion flow: wallet accumulation, activity log, stats, spending total"');
  console.log('  git push');
}
console.log('\n⚠️  Also run this SQL in Supabase SQL Editor:');
console.log(`
CREATE OR REPLACE FUNCTION add_points(p_phone TEXT, p_amount INT)
RETURNS VOID AS $$
BEGIN
  INSERT INTO points (phone, total_points, updated_at)
  VALUES (p_phone, p_amount, NOW())
  ON CONFLICT (phone) DO UPDATE
  SET total_points = points.total_points + p_amount,
      updated_at   = NOW();
END;
$$ LANGUAGE plpgsql;
`);
