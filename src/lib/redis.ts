// Thin Upstash Redis REST client — no SDK dependency, since Upstash's REST
// API is just two HTTP calls (GET/SET with an optional EX). Upstash was
// chosen specifically because it's REST-based: a serverless function here
// can't hold a persistent TCP connection the way a long-running server
// could, which rules out a classic Redis client (ioredis/node-redis).
//
// Safe by construction: every function here no-ops (cache miss / silent
// skip) when UPSTASH_REDIS_REST_URL/UPSTASH_REDIS_REST_TOKEN aren't set,
// so a route using this works identically — just uncached — before those
// env vars exist, and never throws if Upstash itself is slow or down.
// Never a source of truth: a cache miss or failure always falls through
// to the real fetch, same as core/data_cache.dart's client-side cache.

const REST_URL = import.meta.env.UPSTASH_REDIS_REST_URL as string | undefined;
const REST_TOKEN = import.meta.env.UPSTASH_REDIS_REST_TOKEN as string | undefined;

function configured() {
  return Boolean(REST_URL && REST_TOKEN);
}

async function command(args: (string | number)[]): Promise<unknown> {
  if (!configured()) {
    // Temporary — every /api/points/summary request has been a cache MISS
    // even back-to-back within the same second, which a working 20s-TTL
    // cache can't produce. Logging which branch fires narrows it down to
    // "env vars never made it into this build" vs. "Upstash itself is
    // rejecting/failing the request". Remove once Redis is confirmed
    // actually connecting.
    console.log('redis: not configured (REST_URL or REST_TOKEN missing at build time)');
    return null;
  }
  try {
    const res = await fetch(`${REST_URL}/${args.map((a) => encodeURIComponent(String(a))).join('/')}`, {
      headers: { Authorization: `Bearer ${REST_TOKEN}` },
      signal: AbortSignal.timeout(2000),
    });
    if (!res.ok) {
      console.log(`redis: command failed, status=${res.status} ${res.statusText}`);
      return null;
    }
    const data = await res.json();
    if (data?.error) {
      console.log(`redis: command returned error: ${JSON.stringify(data.error).slice(0, 200)}`);
      return null;
    }
    return data?.result ?? null;
  } catch (err) {
    console.log(`redis: command threw: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

/** Returns the cached, JSON-parsed value for `key`, or null on a miss/error/unconfigured cache. */
export async function cacheGet<T>(key: string): Promise<T | null> {
  const raw = await command(['get', key]);
  if (typeof raw !== 'string') return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

/** Stores `value` under `key` for `ttlSeconds` (default 30s) — a failure here is silent, never thrown. */
export async function cacheSet(key: string, value: unknown, ttlSeconds = 30): Promise<void> {
  if (!configured()) return;
  try {
    const res = await fetch(`${REST_URL}/set/${encodeURIComponent(key)}/${encodeURIComponent(JSON.stringify(value))}?EX=${ttlSeconds}`, {
      headers: { Authorization: `Bearer ${REST_TOKEN}` },
      signal: AbortSignal.timeout(2000),
    });
    // Temporary — every GET has come back a clean miss with no error from
    // `command()` above, which only makes sense if SET is the one quietly
    // failing. This branch had no logging at all before, so a failing SET
    // was invisible. Remove once Redis is confirmed actually connecting.
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      console.log(`redis: SET failed, status=${res.status} ${res.statusText} body=${body.slice(0, 200)}`);
      return;
    }
    const data = await res.json().catch(() => null);
    if (data?.error) {
      console.log(`redis: SET returned error: ${JSON.stringify(data.error).slice(0, 200)}`);
    }
  } catch (err) {
    console.log(`redis: SET threw: ${err instanceof Error ? err.message : String(err)}`);
    // Cache is a pure speed optimization — a failed write just means the
    // next read is a genuine cache miss, same as today.
  }
}

/**
 * Fetch-through helper: serves the cached value if present, otherwise calls
 * `fetchFresh`, caches its result, and returns it. `fetchFresh`'s own
 * errors are never swallowed — only the cache layer around it is silent.
 * A `null` return from `fetchFresh` is treated as "this attempt failed,
 * don't cache it" (not as a cacheable value) — otherwise a transient
 * upstream failure would get served back as "the answer" for the rest of
 * the TTL even after the real source recovers.
 */
export async function cached<T>(key: string, ttlSeconds: number, fetchFresh: () => Promise<T | null>): Promise<T | null> {
  const hit = await cacheGet<T>(key);
  if (hit !== null) return hit;
  const fresh = await fetchFresh();
  if (fresh !== null) await cacheSet(key, fresh, ttlSeconds);
  return fresh;
}
