// Registration load test — simulates N concurrent new-customer sign-ups
// hitting POST /rest/v1/accounts (the same direct-insert path
// AuthRepository.register() uses — see flutter_app/lib/features/auth/
// auth_repository.dart). Every test account is tagged and placed in a
// reserved, clearly-fake phone block so it can be found and deleted
// afterward (see the --cleanup mode below) without touching real users.
//
// Deliberately registration-only: `rides` has no DELETE path at all
// (not even an admin RPC — it's an audit-trail table, delete is revoked
// at the grant level), so a write load test against it would leave
// permanent rows with no way to clean them up. Out of scope here.
//
// Usage:
//   node loadtest-register.mjs <SB_URL> <SB_KEY> run     [totalUsers] [concurrency]
//   node loadtest-register.mjs <SB_URL> <SB_KEY> cleanup
//   node loadtest-register.mjs <SB_URL> <SB_KEY> verify

const [, , SB_URL, SB_KEY, mode, totalUsersArg, concurrencyArg] = process.argv;

if (!SB_URL || !SB_KEY || !mode) {
  console.error('Usage: node loadtest-register.mjs <SB_URL> <SB_KEY> run|cleanup|verify [totalUsers] [concurrency]');
  process.exit(1);
}

const HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' };

// Reserved test block: 01590000000 .. 01590000999 — matches the
// isEgyptianMobile format (01[0125]XXXXXXXX) but is a synthetic range
// extremely unlikely to collide with a real registered number.
const PHONE_PREFIX = '01590000';
const phoneFor = (i) => `${PHONE_PREFIX}${String(i).padStart(3, '0')}`;
const CITIES = ['دمياط الجديدة', 'دمياط', 'كفر سعد', 'فارسكور', 'منية النصر', 'رأس البر', 'الزرقا'];

async function registerUser(i) {
  const phone = phoneFor(i);
  const payload = {
    phone,
    password: 'LoadTest!2026',
    name: `LOADTEST_${i}`,
    username: `loadtest_${i}_${Date.now()}`,
    email: `loadtest+${i}@example.test`,
    role: 'customer',
    city: CITIES[i % CITIES.length],
    national_id: `2900101${String(i).padStart(7, '0')}`, // valid-format: 1990-01-01 + unique suffix
    national_id_expiry: '2030-01-01',
    created_at: new Date().toISOString(),
  };
  const t0 = Date.now();
  try {
    const res = await fetch(`${SB_URL}/rest/v1/accounts`, {
      method: 'POST',
      headers: { ...HEADERS, Prefer: 'return=minimal' },
      body: JSON.stringify(payload),
    });
    return { i, ms: Date.now() - t0, ok: res.ok, status: res.status };
  } catch (e) {
    return { i, ms: Date.now() - t0, ok: false, status: 0, error: String(e.message || e) };
  }
}

async function runLoadTest(totalUsers, concurrency) {
  console.log(`Registration load test: ${totalUsers} simulated sign-ups, concurrency ${concurrency}, target ${SB_URL}`);
  console.log(`Test phone block: ${phoneFor(0)} .. ${phoneFor(totalUsers - 1)}`);
  const all = [];
  const startedAt = Date.now();
  for (let i = 0; i < totalUsers; i += concurrency) {
    const batchSize = Math.min(concurrency, totalUsers - i);
    const batch = await Promise.all(Array.from({ length: batchSize }, (_, k) => registerUser(i + k)));
    all.push(...batch);
    process.stdout.write(`\rProgress: ${Math.min(i + batchSize, totalUsers)}/${totalUsers}`);
  }
  const totalMs = Date.now() - startedAt;
  const ok = all.filter(r => r.ok).length;
  const fail = all.length - ok;
  const latencies = all.map(r => r.ms).sort((a, b) => a - b);
  const p50 = latencies[Math.floor(latencies.length * 0.5)];
  const p95 = latencies[Math.floor(latencies.length * 0.95)];
  const p99 = latencies[Math.floor(latencies.length * 0.99)];
  const max = latencies[latencies.length - 1];

  console.log('\n\n=== Results ===');
  console.log(`Total wall time: ${(totalMs / 1000).toFixed(1)}s`);
  console.log(`requests=${all.length} ok=${ok} fail=${fail} p50=${p50}ms p95=${p95}ms p99=${p99}ms max=${max}ms`);
  console.log(`error_rate: ${(100 * fail / all.length).toFixed(2)}%`);
  console.log(`Effective throughput: ${(all.length / (totalMs / 1000)).toFixed(1)} req/s`);
  if (fail > 0) {
    const samples = all.filter(r => !r.ok).slice(0, 5);
    for (const s of samples) console.log(`  failure[${s.i}]: status=${s.status} ${s.error || ''}`);
  }

  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    const fs = await import('node:fs/promises');
    const md = `## \u{1F680} Registration load test — ${totalUsers} sign-ups (concurrency ${concurrency})\n\n` +
      `**Wall time:** ${(totalMs / 1000).toFixed(1)}s · **Throughput:** ${(all.length / (totalMs / 1000)).toFixed(1)} req/s\n\n` +
      `| Requests | OK | Failed | Error rate | p50 | p95 | p99 | Max |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n` +
      `| ${all.length} | ${ok} | ${fail} | ${(100 * fail / all.length).toFixed(2)}% | ${p50}ms | ${p95}ms | ${p99}ms | ${max}ms |\n\n` +
      `Test accounts tagged \`LOADTEST_*\` in phone block ${phoneFor(0)}..${phoneFor(totalUsers - 1)} — clean up with the \`cleanup\` mode.\n`;
    await fs.appendFile(summaryPath, md);
  }
  if (fail > 0) process.exitCode = 1;
}

async function cleanup() {
  console.log(`Deleting all accounts with phone like ${PHONE_PREFIX}*...`);
  const res = await fetch(`${SB_URL}/rest/v1/accounts?phone=like.${PHONE_PREFIX}*`, {
    method: 'DELETE',
    headers: { ...HEADERS, Prefer: 'return=representation' },
  });
  const text = await res.text();
  let deletedCount = 'unknown';
  try {
    const rows = JSON.parse(text);
    if (Array.isArray(rows)) deletedCount = rows.length;
  } catch { /* non-JSON body, leave as unknown */ }
  console.log(`DELETE status: ${res.status}, deleted: ${deletedCount}`);
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    const fs = await import('node:fs/promises');
    await fs.appendFile(summaryPath, `## \u{1F9F9} Cleanup\n\nDELETE status: ${res.status} — removed ${deletedCount} test account(s) (phone like \`${PHONE_PREFIX}*\`).\n`);
  }
  if (!res.ok) process.exitCode = 1;
}

async function verify() {
  const res = await fetch(`${SB_URL}/rest/v1/accounts?phone=like.${PHONE_PREFIX}*&select=phone`, {
    headers: { ...HEADERS, Prefer: 'count=exact' },
  });
  const rows = await res.json();
  console.log(`Accounts currently matching ${PHONE_PREFIX}*: ${Array.isArray(rows) ? rows.length : 'error'}`);
}

if (mode === 'run') {
  await runLoadTest(parseInt(totalUsersArg || '1000', 10), parseInt(concurrencyArg || '100', 10));
} else if (mode === 'cleanup') {
  await cleanup();
} else if (mode === 'verify') {
  await verify();
} else {
  console.error(`Unknown mode: ${mode}`);
  process.exit(1);
}
