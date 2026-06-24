#!/usr/bin/env node
// Fix: Add icon, route, price fields to localStorage order saves in rides.astro
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'src/pages/rides.astro');
let src = fs.readFileSync(file, 'utf8');
let changed = 0;

// Fix 1: local ride save
const old1 = `orders.unshift({ id: ride?.id || ('R'+Date.now()), type:'ride', from:from.name, to:to.name, name, phone, passengers:pax, payment:pay, fare, eta, distance: roadKm.toFixed(1), status:'pending', createdAt:new Date().toISOString() });`;
const new1 = `orders.unshift({ id: ride?.id || ('R'+Date.now()), type:'ride', icon:'🚗', route:from.name+' → '+to.name, price:fare+' ج.م', from:from.name, to:to.name, name, phone, passengers:pax, payment:pay, fare, eta, distance: roadKm.toFixed(1), status:'pending', createdAt:new Date().toISOString() });`;
if (src.includes(old1)) { src = src.replace(old1, new1); changed++; console.log('✅ Fix 1: local ride save'); }
else if (src.includes(new1)) { console.log('✅ Fix 1: already applied'); }
else { console.error('❌ Fix 1: pattern not found'); }

// Fix 2: airport ride save
const old2 = `orders.unshift({ id: ride?.id || ('R'+Date.now()), type:'airport', from:fromArea.name, to:airport.name, name, phone, passengers:pax, payment:pay, fare:airport.flatFare, eta:airport.driveMins, status:'pending', createdAt:new Date().toISOString() });`;
const new2 = `orders.unshift({ id: ride?.id || ('R'+Date.now()), type:'airport', icon:'✈️', route:fromArea.name+' → '+airport.name, price:airport.flatFare+' ج.م', from:fromArea.name, to:airport.name, name, phone, passengers:pax, payment:pay, fare:airport.flatFare, eta:airport.driveMins, status:'pending', createdAt:new Date().toISOString() });`;
if (src.includes(old2)) { src = src.replace(old2, new2); changed++; console.log('✅ Fix 2: airport ride save'); }
else if (src.includes(new2)) { console.log('✅ Fix 2: already applied'); }
else { console.error('❌ Fix 2: pattern not found'); }

if (changed > 0) {
  fs.writeFileSync(file, src, 'utf8');
  console.log(`\n✅ Done — ${changed} fix(es) applied to src/pages/rides.astro`);
  console.log('Run: git add src/pages/rides.astro && git commit -m "Fix order history: add icon, route, price fields" && git push');
} else {
  console.log('\nNo changes needed.');
}
