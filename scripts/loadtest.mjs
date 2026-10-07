// Lightweight concurrent load test — no external deps (uses global fetch).
// Simulates N "users" hitting a mix of representative READ-ONLY endpoints
// at once, in waves, and reports latency/error stats.
//
// READ-ONLY BY DESIGN — never writes to rides/orders/accounts/wallets,
// only GET-style reads and side-effect-free RPCs, so it can't touch real
// driver dispatch or wallet balances the way an INSERT into `rides` would.
// Meant to be run from GitHub Actions (workflow_dispatch) — this sandbox's
// own network policy blocks direct outbound calls to supabase.co, but
// Actions runners have normal internet access.
//
// Usage: node loadtest.mjs <SB_URL> <SB_ANON_KEY> [totalUsers] [concurrency]

const [, , SB_URL, SB_KEY, totalUsersArg, concurrencyArg] = process.argv;

if (!SB_URL || !SB_KEY) {
  console.error('Usage: node loadtest.mjs <SB_URL> <SB_ANON_KEY> [totalUsers] [concurrency]');
  process.exit(1);
}

const TOTAL_USERS = parseInt(totalUsersArg || '1000', 10);
const CONCURRENCY = parseInt(concurrencyArg || '100', 10); // simultaneous in-flight requests

const HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' };

// Each "user session" does a small realistic sequence of read-only calls,
// similar to opening the app: browse stores, check app settings, look up
// an account by phone, check surge pricing, check driver availability.
async function userSession(i) {
  const results = [];
  const testPhone = `0100${String(1000000 + i).padStart(7, '0')}`;

  const timed = async (label, fn) => {
    const t0 = Date.now();
    try {
      const res = await fn();
      const ms = Date.now() - t0;
      results.push({ label, ms, ok: res.ok, status: res.status });
      return res;
    } catch (e) {
      const ms = Date.now() - t0;
      results.push({ label, ms, ok: false, status: 0, error: String(e.message || e) });
      return null;
    }
  };

  await timed('browse_stores', () =>
    fetch(`${SB_URL}/rest/v1/stores?select=id,name,is_open&limit=20`, { headers: HEADERS }));

  await timed('app_settings', () =>
    fetch(`${SB_URL}/rest/v1/app_settings?select=key,value&limit=10`, { headers: HEADERS }));

  await timed('lookup_account', () =>
    fetch(`${SB_URL}/rest/v1/rpc/lookup_account`, {
      method: 'POST', headers: HEADERS, body: JSON.stringify({ p_phone: testPhone }),
    }));

  await timed('surge_multiplier', () =>
    fetch(`${SB_URL}/rest/v1/rpc/current_surge_multiplier`, {
      method: 'POST', headers: HEADERS, body: JSON.stringify({ p_ride_type: 'local' }),
    }));

  await timed('available_drivers', () =>
    fetch(`${SB_URL}/rest/v1/rpc/get_available_drivers_count`, {
      method: 'POST', headers: HEADERS, body: JSON.stringify({}),
    }));

  return results;
}

async function runBatch(startIdx, count) {
  const promises = [];
  for (let i = startIdx; i < startIdx + count; i++) promises.push(userSession(i));
  return (await Promise.all(promises)).flat();
}

function statsTable(byLabel) {
  const rows = [];
  let totalOk = 0, totalFail = 0, totalCount = 0;
  for (const [label, entries] of Object.entries(byLabel)) {
    const ok = entries.filter(r => r.ok).length;
    const fail = entries.length - ok;
    totalOk += ok; totalFail += fail; totalCount += entries.length;
    const latencies = entries.map(r => r.ms).sort((a, b) => a - b);
    const p50 = latencies[Math.floor(latencies.length * 0.5)];
    const p95 = latencies[Math.floor(latencies.length * 0.95)];
    const p99 = latencies[Math.floor(latencies.length * 0.99)];
    const max = latencies[latencies.length - 1];
    rows.push({ label, count: entries.length, ok, fail, p50, p95, p99, max });
  }
  return { rows, totalOk, totalFail, totalCount };
}

async function main() {
  console.log(`Load test: ${TOTAL_USERS} simulated users, concurrency ${CONCURRENCY}, target ${SB_URL}`);
  const allResults = [];
  const startedAt = Date.now();
  for (let i = 0; i < TOTAL_USERS; i += CONCURRENCY) {
    const batchSize = Math.min(CONCURRENCY, TOTAL_USERS - i);
    const batchResults = await runBatch(i, batchSize);
    allResults.push(...batchResults);
    process.stdout.write(`\rProgress: ${Math.min(i + batchSize, TOTAL_USERS)}/${TOTAL_USERS} users`);
  }
  const totalMs = Date.now() - startedAt;
  console.log('\n\n=== Results ===');
  console.log(`Total wall time: ${(totalMs / 1000).toFixed(1)}s`);

  const byLabel = {};
  for (const r of allResults) {
    byLabel[r.label] ??= [];
    byLabel[r.label].push(r);
  }
  const { rows, totalOk, totalFail, totalCount } = statsTable(byLabel);

  for (const r of rows) {
    console.log(`${r.label.padEnd(18)} requests=${r.count.toString().padEnd(6)} ok=${r.ok.toString().padEnd(6)} fail=${r.fail.toString().padEnd(5)} p50=${r.p50}ms p95=${r.p95}ms p99=${r.p99}ms max=${r.max}ms`);
    if (r.fail > 0) {
      const sample = byLabel[r.label].find(x => !x.ok);
      console.log(`  sample failure: status=${sample.status} ${sample.error || ''}`);
    }
  }
  const errorRate = (100 * totalFail / totalCount).toFixed(2);
  const throughput = (totalCount / (totalMs / 1000)).toFixed(1);
  console.log(`\nTotal requests: ${totalCount}  ok: ${totalOk}  failed: ${totalFail}  error_rate: ${errorRate}%`);
  console.log(`Effective throughput: ${throughput} req/s`);

  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (summaryPath) {
    const fs = await import('node:fs/promises');
    let md = `## \u{1F680} Load test results — ${TOTAL_USERS} simulated users (concurrency ${CONCURRENCY})\n\n`;
    md += `**Wall time:** ${(totalMs / 1000).toFixed(1)}s · **Throughput:** ${throughput} req/s · **Error rate:** ${errorRate}%\n\n`;
    md += `| Endpoint | Requests | OK | Failed | p50 | p95 | p99 | Max |\n`;
    md += `| --- | --- | --- | --- | --- | --- | --- | --- |\n`;
    for (const r of rows) {
      md += `| ${r.label} | ${r.count} | ${r.ok} | ${r.fail} | ${r.p50}ms | ${r.p95}ms | ${r.p99}ms | ${r.max}ms |\n`;
    }
    await fs.appendFile(summaryPath, md);
  }

  if (totalFail > 0) process.exitCode = 1;
}

main();
