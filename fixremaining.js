// fixremaining.js — apply remaining fixes and push
// Run: node fixremaining.js
const fs = require('fs');
const { execSync } = require('child_process');

let changed = 0;

function fix(filePath, label, oldStr, newStr) {
  let src = fs.readFileSync(filePath, 'utf8').replace(/\r\n/g, '\n');
  if (src.includes(newStr.trim().slice(0, 60))) {
    console.log(`[skip] ${label} already applied`);
    return;
  }
  if (!src.includes(oldStr.trim().slice(0, 60))) {
    console.log(`[!] ${label} — old string not found`);
    return;
  }
  fs.writeFileSync(filePath, src.replace(oldStr, newStr), 'utf8');
  console.log(`[ok]  ${label}`);
  changed++;
}

// ── 1. profile.astro: include rides fare in total spending ──────────────────
fix(
  'src/pages/profile.astro',
  'profile: rides fare in totalSpent',
  `    const totalSpent = orders
      .filter(o => o.status === 'delivered' || o.status === 'completed')
      .reduce((s, o) => s + (Number(o.total) || 0), 0);`,
  `    const totalSpent =
      orders.filter(o => o.status === 'delivered' || o.status === 'completed')
            .reduce((s, o) => s + (Number(o.total) || 0), 0)
      + rides.filter(r => r.status === 'completed')
             .reduce((s, r) => s + (Number(r.fare) || 0), 0);`
);

// ── 2. driver-dashboard: use RPC for wallet accumulation ────────────────────
fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: wallet accumulation via RPC',
  `      // Upsert driver wallet
      fetch(\`\${SB_URL}/rest/v1/wallets\`, {
        method: 'POST',
        headers: { ...SB_H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ phone, balance: driverEarn, updated_at: now }),
      }),`,
  `      // Accumulate driver wallet balance via RPC (prevents overwrite)
      fetch(\`\${SB_URL}/rest/v1/rpc/add_wallet_balance\`, {
        method: 'POST',
        headers: { ...SB_H },
        body: JSON.stringify({ p_phone: phone, p_amount: driverEarn }),
      }),`
);

// ── 3. driver-dashboard: use RPC for points accumulation ───────────────────
fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: points accumulation via RPC',
  `      // Upsert points total
      fetch(\`\${SB_URL}/rest/v1/points\`, {
        method: 'POST',
        headers: { ...SB_H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ phone, total_points: pointsEarned, updated_at: now }),
      }),`,
  `      // Accumulate points total via RPC (prevents overwrite)
      fetch(\`\${SB_URL}/rest/v1/rpc/add_points\`, {
        method: 'POST',
        headers: { ...SB_H },
        body: JSON.stringify({ p_phone: phone, p_amount: pointsEarned }),
      }),`
);

// ── 4. driver-dashboard: airport ride type detection ───────────────────────
fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: detect airport ride_type',
  `    if (!currentRide) return;
    await patchRide(currentRide.id, { status: 'completed', completed_at: new Date().toISOString() });
    const fare   = currentRide.fare;
    const rideId = currentRide.id;`,
  `    if (!currentRide) return;
    await patchRide(currentRide.id, { status: 'completed', completed_at: new Date().toISOString() });
    const fare     = currentRide.fare;
    const rideId   = currentRide.id;
    const rideType = currentRide.ride_type === 'airport' ? 'airport' : 'ride';`
);

fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: pass rideType to recordCompletion',
  `    await recordCompletion('ride', rideId, fare || 0);
    currentRide = null;`,
  `    await recordCompletion(rideType, rideId, fare || 0);
    currentRide = null;`
);

// ── 5. driver-dashboard: activity log refresh after completion ─────────────
fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: activity refresh after delivery',
  `      showToast(\`تم توصيل الطلب! أرباح +\${fee} ج.م 🎉\`);
      return;`,
  `      showToast(\`تم توصيل الطلب! أرباح +\${fee} ج.م 🎉\`);
      setTimeout(() => loadActivityLog(), 600);
      return;`
);

fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: activity refresh after ride',
  `    showToast(\`رحلة منتهية! أرباح +\${fare} ج.م 🎉\`);
  });`,
  `    showToast(\`رحلة منتهية! أرباح +\${fare} ج.م 🎉\`);
    setTimeout(() => loadActivityLog(), 600);
  });`
);

// ── 6. driver-dashboard: merchant wallet credit after delivery ─────────────
fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: merchant wallet credit',
  `      const fee = currentOrder.delivery_fee || 0;
      const orderId = currentOrder.id;
      try {`,
  `      const fee = currentOrder.delivery_fee || 0;
      const orderId = currentOrder.id;
      const storeId = currentOrder.store_id;
      try {`
);

fix(
  'src/pages/driver-dashboard.astro',
  'driver-dashboard: merchant wallet credit block',
  `      await recordCompletion('delivery', orderId, fee);
      currentOrder = null;`,
  `      await recordCompletion('delivery', orderId, fee);
      // Credit merchant wallet with order subtotal (order total minus delivery fee)
      if (storeId) {
        try {
          const storeData = await fetch(\`\${SB_URL}/rest/v1/stores?id=eq.\${storeId}&select=owner_phone\`, { headers: SB_H }).then(r => r.json());
          const mPhone = storeData?.[0]?.owner_phone;
          if (mPhone) {
            const subtotal = Math.max(0, (currentOrder.subtotal || currentOrder.total || 0) - fee);
            await Promise.allSettled([
              fetch(\`\${SB_URL}/rest/v1/rpc/add_wallet_balance\`, { method: 'POST', headers: SB_H, body: JSON.stringify({ p_phone: mPhone, p_amount: subtotal }) }),
              fetch(\`\${SB_URL}/rest/v1/wallet_transactions\`, { method: 'POST', headers: { ...SB_H, Prefer: 'return=minimal' }, body: JSON.stringify({ phone: mPhone, amount: subtotal, type: 'earning', reference_id: orderId, note: \`أرباح طلب #\${currentOrder.code || orderId}\`, created_at: new Date().toISOString() }) }),
            ]);
          }
        } catch {}
      }
      currentOrder = null;`
);

if (changed > 0) {
  try {
    execSync('git add src/pages/driver-dashboard.astro src/pages/profile.astro', { stdio: 'inherit' });
    execSync(`git commit -m "fix: wallet accumulation, merchant credit, activity refresh, airport ride type"`, { stdio: 'inherit' });
    execSync('git push -u origin claude/dreamy-johnson-nuzHs', { stdio: 'inherit' });
    console.log('\n✅ All done — pushed to remote!');
  } catch (e) {
    console.error('Git error:', e.message);
  }
} else {
  console.log('\nNo changes needed — all fixes already applied.');
}
