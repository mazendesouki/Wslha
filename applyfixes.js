// apply-fixes.js  — run with:  node apply-fixes.js
const fs = require('fs');

// ── 1. package.json ──────────────────────────────────────────────
let pkg = fs.readFileSync('package.json', 'utf8');
pkg = pkg.replace('"deploy": "astro build && firebase deploy --only hosting"',
                  '"deploy": "astro build && vercel --prod"');
fs.writeFileSync('package.json', pkg);
console.log('✓ package.json');

// ── 2. .github/workflows/deploy.yml ─────────────────────────────
fs.writeFileSync('.github/workflows/deploy.yml',
`name: Deploy to Vercel

on:
  push:
    branches:
      - main
      - master
      - claude/dreamy-johnson-nuzHs

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build

      - name: Deploy to Vercel
        run: npx vercel --prod --token "$VERCEL_TOKEN"
        env:
          VERCEL_TOKEN: \${{ secrets.VERCEL_TOKEN }}
`);
console.log('✓ .github/workflows/deploy.yml');

// ── 3. driver-dashboard.astro ────────────────────────────────────
let dash = fs.readFileSync('src/pages/driver-dashboard.astro', 'utf8');

// a) Add reply CSS after .rating-item__comment rule
dash = dash.replace(
  '  .rating-item__comment { font-size: var(--text-xs); color: var(--color-text-muted); margin-top: 2px; }',
  `  .rating-item__comment { font-size: var(--text-xs); color: var(--color-text-muted); margin-top: 2px; }
  .rating-item__reply { margin-top:6px; padding:6px 10px; background:#eff6ff; border-radius:8px; font-size:var(--text-xs); color:#1e40af; border-right:3px solid #3b82f6; }
  .rating-item__reply-label { font-size:10px; color:#64748b; margin-bottom:2px; }
  .rating-reply-form { margin-top:6px; display:flex; gap:6px; }
  .rating-reply-input { flex:1; padding:6px 10px; border:1.5px solid var(--color-border); border-radius:8px; font-size:var(--text-xs); resize:none; direction:rtl; font-family:var(--font-body); background:var(--color-bg); color:var(--color-text); }
  .rating-reply-send { padding:6px 14px; background:var(--color-primary); color:#fff; border:none; border-radius:8px; font-size:var(--text-xs); cursor:pointer; }`
);

// b) stat-rating: emoji → dash, move emoji to label
dash = dash.replace(
  '<div class="stat-card__val" id="stat-rating">⭐</div><div class="stat-card__key">التقييم</div>',
  '<div class="stat-card__val" id="stat-rating">—</div><div class="stat-card__key">⭐ التقييم</div>'
);

// c) <script> → <script is:inline>
dash = dash.replace('\n<script>\n  const SB_URL', '\n<script is:inline>\n  const SB_URL');

// d) Add loadRatingStat() call after loadApprovalStatus()
dash = dash.replace(
  '    loadApprovalStatus();\n  }',
  '    loadApprovalStatus();\n    loadRatingStat();\n  }'
);

// e) Add loadRatingStat + sendReply functions before loadApprovalStatus
dash = dash.replace(
  '  /* ── Load approval status ── */\n  async function loadApprovalStatus()',
  `  /* ── Load approval status ── */
  async function loadRatingStat() {
    if (!driver) return;
    try {
      const res = await fetch(\`\${SB_URL}/rest/v1/ratings?driver_phone=eq.\${encodeURIComponent(driver.phone)}&select=rating&limit=100\`, { headers: SB_H });
      if (!res.ok) return;
      const rts = await res.json();
      const el = document.getElementById('stat-rating');
      if (!el) return;
      el.textContent = (Array.isArray(rts) && rts.length)
        ? (rts.reduce((s, r) => s + r.rating, 0) / rts.length).toFixed(1)
        : '—';
    } catch {}
  }

  function sendReply(ratingId, btn) {
    const form  = btn.closest('.rating-reply-form');
    const input = form && form.querySelector('textarea');
    if (!input) return;
    const reply = input.value.trim();
    if (!reply) { input.focus(); return; }
    btn.disabled = true; btn.textContent = '...';
    fetch(\`\${SB_URL}/rest/v1/ratings?id=eq.\${ratingId}\`, {
      method: 'PATCH',
      headers: { ...SB_H, Prefer: 'return=minimal' },
      body: JSON.stringify({ driver_reply: reply }),
    }).then(res => {
      if (res.ok) {
        form.outerHTML = \`<div class="rating-item__reply"><div class="rating-item__reply-label">ردك:</div>\${reply}</div>\`;
      } else { btn.disabled = false; btn.textContent = 'إرسال'; }
    }).catch(() => { btn.disabled = false; btn.textContent = 'إرسال'; });
  }

  async function loadApprovalStatus()`
);

// f) Ratings query: add id, driver_reply, increase limit
dash = dash.replace(
  "select=rating,comment,service_type,created_at&order=created_at.desc&limit=10",
  "select=id,rating,comment,service_type,created_at,driver_reply&order=created_at.desc&limit=20"
);

// g) stat-rating textContent: remove emoji prefix
dash = dash.replace(
  "document.getElementById('stat-rating').textContent  = `⭐ ${avg.toFixed(1)}`;",
  "document.getElementById('stat-rating').textContent  = avg.toFixed(1);"
);

// h) Rating item render: add reply form
dash = dash.replace(
  "return `<div class=\"rating-item\"><div class=\"rating-item__top\"><span class=\"rating-item__stars\">${s}</span><span class=\"rating-item__date\">${d}</span></div>${r.comment ? `<div class=\"rating-item__comment\">\"${r.comment}\"</div>` : ''}</div>`;",
  `const typeIcon = r.service_type === 'delivery' ? '🛵' : r.service_type === 'airport' ? '✈️' : '🚗';
          const commentHtml = r.comment ? \`<div class="rating-item__comment">"\${r.comment}"</div>\` : '';
          const replyHtml = r.driver_reply
            ? \`<div class="rating-item__reply"><div class="rating-item__reply-label">ردك:</div>\${r.driver_reply}</div>\`
            : \`<div class="rating-reply-form"><textarea class="rating-reply-input" rows="1" placeholder="اكتب ردك..."></textarea><button class="rating-reply-send" onclick="sendReply('\${r.id}',this)">إرسال</button></div>\`;
          return \`<div class="rating-item" id="rt-\${r.id}"><div class="rating-item__top"><span class="rating-item__stars">\${s}</span><span class="rating-item__date">\${typeIcon} \${d}</span></div>\${commentHtml}\${replyHtml}</div>\`;`
);

// i) Wallet: replace upsert with RPC
dash = dash.replace(
  `      // Upsert driver wallet
      fetch(\`\${SB_URL}/rest/v1/wallets\`, {
        method: 'POST',
        headers: { ...SB_H, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ phone, balance: driverEarn, updated_at: now }),
      }),`,
  `      fetch(\`\${SB_URL}/rest/v1/rpc/add_wallet_balance\`, {
        method: 'POST',
        headers: { ...SB_H },
        body: JSON.stringify({ p_phone: phone, p_amount: driverEarn }),
      }),`
);

fs.writeFileSync('src/pages/driver-dashboard.astro', dash);
console.log('✓ driver-dashboard.astro');

// ── 4. profile.astro ─────────────────────────────────────────────
let profile = fs.readFileSync('src/pages/profile.astro', 'utf8');

// a) stat-spent → stat-wallet
profile = profile.replace(
  `      <div class="pf-stat pf-stat--green">
        <span class="pf-stat__num" id="stat-spent">0 ج.م</span>
        <span class="pf-stat__lbl">💰 إنفاق</span>
      </div>`,
  `      <div class="pf-stat pf-stat--green" style="cursor:pointer" onclick="location.href='/wallet'">
        <span class="pf-stat__num" id="stat-wallet">—</span>
        <span class="pf-stat__lbl">💳 المحفظة</span>
      </div>`
);

// b) Add fetchWallet function after fetchAccount
profile = profile.replace(
  `  async function fetchDriverApp(phone) {`,
  `  async function fetchWallet(phone) {
    const intl  = intlPhone(phone);
    const local = localPhone(phone);
    const data  = await sbFetch(SB_URL + '/rest/v1/wallets?or=(phone.eq.' + encodeURIComponent(intl) + ',phone.eq.' + encodeURIComponent(local) + ')&select=balance&limit=1');
    return Array.isArray(data) && data[0] ? data[0] : null;
  }
  async function fetchDriverApp(phone) {`
);

// c) Remove stat-spent line from renderStats
profile = profile.replace(
  `    $('stat-orders').textContent = orders.length;\n    $('stat-spent').textContent  = fmt(Math.round(totalSpent)) + ' ج.م';\n    $('stat-rides').textContent`,
  `    $('stat-orders').textContent = orders.length;\n    $('stat-rides').textContent`
);

// d) Add fetchWallet to fetches array
profile = profile.replace(
  'var fetches = [fetchAccount(phone), fetchOrders(phone), fetchRides(phone)];',
  'var fetches = [fetchAccount(phone), fetchOrders(phone), fetchRides(phone), fetchWallet(phone)];'
);

// e) Update result indices and add wallet display
profile = profile.replace(
  `        var sbRides  = results[2];
        var appData  = results[3] || null;
        var acc      = sbAcc || lsAcc;
        var orders   = mergeOrders(sbOrders || [], lsOrders);
        var acctStatus = acc ? (acc.status || null) : null;
        showContent(acc, orders, sbRides || [], acctStatus, appData);`,
  `        var sbRides  = results[2];
        var wallet   = results[3] || null;
        var appData  = results[4] || null;
        var acc      = sbAcc || lsAcc;
        var orders   = mergeOrders(sbOrders || [], lsOrders);
        var acctStatus = acc ? (acc.status || null) : null;
        var wEl = $('stat-wallet');
        if (wEl) wEl.textContent = wallet ? (Math.round(wallet.balance || 0) + ' ج.م') : '0 ج.م';
        showContent(acc, orders, sbRides || [], acctStatus, appData);`
);

fs.writeFileSync('src/pages/profile.astro', profile);
console.log('✓ profile.astro');

console.log('\n✅ Done! Now run:\n  git add -A && git commit -m "fix: dashboard + wallet + Vercel" && git push origin claude/dreamy-johnson-nuzHs');
