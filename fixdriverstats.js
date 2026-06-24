#!/usr/bin/env node
// Fix: Driver stats isolated per driver (phone-specific localStorage + Supabase source)
const fs = require('fs'), path = require('path');
const file = path.join(__dirname, 'src/pages/driver-dashboard.astro');
let src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
let changed = 0;

function apply(old, neo, label) {
  if (src.includes(neo.trim().slice(0, 60))) { console.log('  ✅ already applied: ' + label); return; }
  if (!src.includes(old)) { console.error('  ❌ not found: ' + label); return; }
  src = src.replace(old, neo); changed++; console.log('  ✅ ' + label);
}

// 1. Phone-specific localStorage key on initial load + add loadTodayStats function
apply(
  `  /* ── Stats ── */
  let todayStats = { trips: 0, earn: 0 };
  try {
    const key = 'wslha_driver_stats_' + new Date().toDateString();
    todayStats = JSON.parse(localStorage.getItem(key) || '{"trips":0,"earn":0}');
  } catch {}
  function renderStats() {
    document.getElementById('stat-trips').textContent = String(todayStats.trips);
    document.getElementById('stat-earn').textContent  = String(todayStats.earn);
  }
  renderStats();`,
  `  /* ── Stats ── */
  let todayStats = { trips: 0, earn: 0 };
  try {
    const key = 'wslha_driver_stats_' + (driver?.phone || '') + '_' + new Date().toDateString();
    todayStats = JSON.parse(localStorage.getItem(key) || '{"trips":0,"earn":0}');
  } catch {}
  function renderStats() {
    document.getElementById('stat-trips').textContent = String(todayStats.trips);
    document.getElementById('stat-earn').textContent  = String(todayStats.earn);
  }
  renderStats();

  /* ── Load today stats from Supabase (accurate, per-driver) ── */
  async function loadTodayStats() {
    if (!driver?.phone) return;
    const today = new Date().toISOString().split('T')[0];
    try {
      const [ridesRes, walletRes] = await Promise.allSettled([
        fetch(\`\${SB_URL}/rest/v1/rides?driver_phone=eq.\${encodeURIComponent(driver.phone)}&status=eq.completed&completed_at=gte.\${today}&select=fare\`, { headers: SB_H }),
        fetch(\`\${SB_URL}/rest/v1/wallet_transactions?phone=eq.\${encodeURIComponent(driver.phone)}&type=eq.earning&created_at=gte.\${today}&select=amount\`, { headers: SB_H }),
      ]);
      let trips = todayStats.trips, earn = todayStats.earn;
      if (ridesRes.status === 'fulfilled' && ridesRes.value.ok) {
        const rides = await ridesRes.value.json();
        if (Array.isArray(rides)) trips = rides.length;
      }
      if (walletRes.status === 'fulfilled' && walletRes.value.ok) {
        const txs = await walletRes.value.json();
        if (Array.isArray(txs)) earn = Math.round(txs.reduce((s, t) => s + (Number(t.amount) || 0), 0));
      }
      todayStats = { trips, earn };
      renderStats();
      const key = 'wslha_driver_stats_' + driver.phone + '_' + new Date().toDateString();
      localStorage.setItem(key, JSON.stringify(todayStats));
    } catch {}
  }`,
  'per-driver stats key + loadTodayStats()'
);

// 2. Phone-specific key on completion save (replace all occurrences)
const OLD_KEY = `'wslha_driver_stats_' + new Date().toDateString()`;
const NEW_KEY = `'wslha_driver_stats_' + (driver?.phone || '') + '_' + new Date().toDateString()`;
if (src.includes(OLD_KEY)) {
  const count = src.split(OLD_KEY).length - 1;
  src = src.split(OLD_KEY).join(NEW_KEY);
  changed += count;
  console.log(`  ✅ fixed ${count} completion key(s) to be phone-specific`);
} else if (src.includes(NEW_KEY)) {
  console.log('  ✅ already applied: completion keys phone-specific');
} else {
  console.error('  ❌ completion key pattern not found');
}

// 3. Call loadTodayStats on startup
apply(
  `    loadApprovalStatus();`,
  `    loadApprovalStatus();
    loadTodayStats();`,
  'call loadTodayStats on startup'
);

if (changed > 0) {
  fs.writeFileSync(file, src, 'utf8');
  console.log(`\n✅ Done — ${changed} change(s) applied`);
  console.log('Run:');
  console.log('  git add src/pages/driver-dashboard.astro');
  console.log('  git commit -m "fix: driver stats isolated per driver"');
  console.log('  git push');
} else {
  console.log('\nNo changes needed.');
}
