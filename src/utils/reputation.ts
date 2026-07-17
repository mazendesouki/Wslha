// ─────────────────────────────────────────────────────────────
// Rating stats + badge thresholds shared across driver/customer/
// merchant profiles. Badges are a pure function of live rating
// numbers (never stored) so they're always current — no separate
// "recalculate badges" step is needed anywhere.
// rides.astro runs a `define:vars` inline script and can't import
// this module — it embeds the SAME logic inline. Keep both in sync.
// ─────────────────────────────────────────────────────────────

export interface RatingStats {
  avg: number;
  count: number;
  satisfactionPct: number; // % of ratings >= 4 stars
}

export function computeRatingStats(ratings: number[]): RatingStats {
  if (!ratings.length) return { avg: 0, count: 0, satisfactionPct: 0 };
  const avg = ratings.reduce((s, r) => s + r, 0) / ratings.length;
  const satisfied = ratings.filter(r => r >= 4).length;
  return { avg, count: ratings.length, satisfactionPct: Math.round((satisfied / ratings.length) * 100) };
}

// Thresholds live in one place so they're easy to tune later.
export const BADGE_THRESHOLDS = { minAvg: 4.5, minCount: 5 };

export function isTopRated(stats: RatingStats): boolean {
  return stats.count >= BADGE_THRESHOLDS.minCount && stats.avg >= BADGE_THRESHOLDS.minAvg;
}

export const BADGE_LABELS = {
  driver:   '🏆 سائق متميز',
  customer: '⭐ عميل مميز',
  merchant: '🏆 تاجر معتمد',
} as const;

export const AC_BADGE_LABEL = '❄️ سيارة مكيفة';

export function ratingStarsText(avg: number): string {
  const rounded = Math.round(avg);
  return '⭐'.repeat(Math.max(0, Math.min(5, rounded))) + '☆'.repeat(5 - Math.max(0, Math.min(5, rounded)));
}
