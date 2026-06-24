#!/usr/bin/env node
// Fix: Airport bookings now insert into Supabase so drivers receive live notifications
const fs = require('fs'), path = require('path');
const file = path.join(__dirname, 'src/pages/airport.astro');
let src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');

const OLD = `      try {
        const existing = JSON.parse(localStorage.getItem('wslha_orders') || '[]');
        existing.unshift(order);
        localStorage.setItem('wslha_orders', JSON.stringify(existing));
      } catch { /* storage unavailable */ }`;

const NEW = `      try {
        const existing = JSON.parse(localStorage.getItem('wslha_orders') || '[]');
        existing.unshift(order);
        localStorage.setItem('wslha_orders', JSON.stringify(existing));
      } catch { /* storage unavailable */ }

      // Insert into Supabase so online drivers receive the request via Realtime
      try {
        const _SB = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
        const _KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
        const _H = { apikey: _KEY, Authorization: 'Bearer ' + _KEY, 'Content-Type': 'application/json', Prefer: 'return=representation' };
        const payRes = await fetch(_SB + '/rest/v1/rides', {
          method: 'POST', headers: _H,
          body: JSON.stringify({
            customer_phone: order.phone,
            customer_name: order.recipient,
            from_area: fromArea,
            from_lat: fromAreaPlace?.lat ?? 0,
            from_lng: fromAreaPlace?.lng ?? 0,
            to_area: selectedAirport.name,
            to_lat: 0, to_lng: 0,
            distance_km: selectedAirport.distanceKm,
            fare: c.total,
            eta_minutes: selectedAirport.driveMinutes,
            passengers: pax,
            payment: (document.querySelector('input[name="payment"]:checked'))?.value || 'cash',
            notes: \`✈️ \${order.airline || ''} \${order.flightNo || ''} — استلام: \${order.address} — إقلاع: \${c.flight?.toLocaleString('ar-EG') || ''} — سيارة: \${order.vehicleName} — شنط: \${bagsVal}\`,
            status: 'pending',
            ride_type: 'airport',
          }),
        });
        if (payRes.ok) {
          const rows = await payRes.json();
          if (Array.isArray(rows) && rows[0]?.id) order.supabase_id = rows[0].id;
        }
      } catch { /* Supabase unavailable — order saved locally */ }`;

if (src.includes('Supabase so online drivers')) {
  console.log('✅ already applied: airport Supabase INSERT');
} else if (src.includes(OLD)) {
  src = src.replace(OLD, NEW);
  fs.writeFileSync(file, src, 'utf8');
  console.log('✅ Fix applied: airport bookings now saved to Supabase');
  console.log('\nRun:');
  console.log('  git add src/pages/airport.astro');
  console.log('  git commit -m "fix: airport bookings insert into Supabase for driver notifications"');
  console.log('  git push');
} else {
  console.error('❌ Pattern not found — file may have changed');
}
