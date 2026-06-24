#!/usr/bin/env node
// Fix: Add live driver notifications (sound, browser push, vibration, pulse animation)
const fs = require('fs'), path = require('path');
const file = path.join(__dirname, 'src/pages/driver-dashboard.astro');
// Normalize CRLF → LF so patterns work on Windows
let src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
let changed = 0;

function apply(old, neo, label) {
  if (src.includes(neo.trim().slice(0, 50))) { console.log('  ✅ already applied: ' + label); return; }
  if (!src.includes(old)) { console.error('  ❌ not found: ' + label); return; }
  src = src.replace(old, neo); changed++;
  console.log('  ✅ ' + label);
}

// 1. Pulse CSS — insert after .ride-req-card closing brace
apply(
  `  #ride-request.visible { bottom: 0; }
  .ride-req-card {
    background: #fff; border-radius: var(--radius-xl);
    box-shadow: 0 -4px 40px rgba(0,0,0,.25), 0 0 0 1px rgba(0,0,0,.06);
    overflow: hidden; max-width: 480px; margin: 0 auto;
  }`,
  `  #ride-request.visible { bottom: 0; }
  .ride-req-card {
    background: #fff; border-radius: var(--radius-xl);
    box-shadow: 0 -4px 40px rgba(0,0,0,.25), 0 0 0 1px rgba(0,0,0,.06);
    overflow: hidden; max-width: 480px; margin: 0 auto;
  }
  @keyframes req-pulse {
    0%,100% { box-shadow: 0 -4px 40px rgba(0,0,0,.25), 0 0 0 1px rgba(0,0,0,.06); }
    50%      { box-shadow: 0 -4px 48px rgba(59,130,246,.7), 0 0 0 5px rgba(59,130,246,.25); }
  }
  #ride-request.visible .ride-req-card { animation: req-pulse 1s ease-in-out infinite; }`,
  'pulse animation CSS'
);

// 2. Notification helpers + ride alert
apply(
  `  function hideRideRequest() {
    document.getElementById('ride-request').classList.remove('visible');
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
  }

  function showRideRequest(ride) {
    pendingRide = ride;`,
  `  /* ── Notification helpers ── */
  function playAlert() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      [[880,0],[660,0.18],[880,0.36]].forEach(([freq,t]) => {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.connect(g); g.connect(ctx.destination);
        o.type = 'sine'; o.frequency.value = freq;
        g.gain.setValueAtTime(0.5, ctx.currentTime + t);
        g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.17);
        o.start(ctx.currentTime + t); o.stop(ctx.currentTime + t + 0.18);
      });
    } catch {}
    if (navigator.vibrate) navigator.vibrate([150, 80, 150, 80, 300]);
  }

  function pushNotify(title, body) {
    if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
    try {
      const n = new Notification(title, { body, icon: '/favicon.ico', tag: 'wslha-req', requireInteraction: true });
      n.onclick = () => { window.focus(); n.close(); };
    } catch {}
  }

  async function ensureNotifyPermission() {
    if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
      await Notification.requestPermission();
    }
  }

  function hideRideRequest() {
    document.getElementById('ride-request').classList.remove('visible');
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
  }

  function showRideRequest(ride) {
    playAlert();
    pushNotify('\u{1F697} طلب رحلة جديد!', \`\${ride.from_area || ''} ← \${ride.to_area || ''} — \${ride.fare || ''} ج.م\`);
    pendingRide = ride;`,
  'notification helpers + ride alert'
);

// 3. Order notification alert
apply(
  `  /* ── Delivery-order request (HungerStation-style) ── */
  function showOrderRequest(order) {
    pendingOrder = order;`,
  `  /* ── Delivery-order request (HungerStation-style) ── */
  function showOrderRequest(order) {
    playAlert();
    pushNotify('\u{1F6F5} طلب توصيل جديد!', \`من \${order.store_name || 'المتجر'} — \${order.delivery_fee || 20} ج.م\`);
    pendingOrder = order;`,
  'order notification alert'
);

// 4. Request permission on go online
apply(
  `  /* ── Go online (shared by auto-activate and toggle) ── */
  async function goOnline() {
    isOnline = true;`,
  `  /* ── Go online (shared by auto-activate and toggle) ── */
  async function goOnline() {
    isOnline = true;
    await ensureNotifyPermission();`,
  'request permission on go online'
);

if (changed > 0) {
  fs.writeFileSync(file, src, 'utf8');
  console.log(`\n✅ Done — ${changed} fix(es) applied to driver-dashboard.astro`);
  console.log('Run:');
  console.log('  git add src/pages/driver-dashboard.astro');
  console.log('  git commit -m "feat: live driver notifications — sound, browser push, vibration, pulse"');
  console.log('  git push');
} else {
  console.log('\nNo changes applied.');
}
