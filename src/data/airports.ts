// Egyptian airports served from Damietta governorate.
// Pricing model updated June 2026 for current Egyptian fuel costs.

// ─── Airports ────────────────────────────────────────────────────────────────
export interface Airport {
  id: string;
  name: string;
  city: string;
  code: string;
  distanceKm: number;
  driveMinutes: number;
}

export const AIRPORTS: Airport[] = [
  { id: 'cai', name: 'مطار القاهرة الدولي',        city: 'القاهرة',      code: 'CAI', distanceKm: 200, driveMinutes: 165 },
  { id: 'spx', name: 'مطار سفنكس الدولي',          city: 'الجيزة',       code: 'SPX', distanceKm: 215, driveMinutes: 180 },
  { id: 'hbe', name: 'مطار برج العرب (الإسكندرية)', city: 'الإسكندرية',   code: 'HBE', distanceKm: 250, driveMinutes: 180 },
  { id: 'psd', name: 'مطار بورسعيد',               city: 'بورسعيد',      code: 'PSD', distanceKm: 85,  driveMinutes: 80  },
  { id: 'muh', name: 'مطار مرسى مطروح',            city: 'مرسى مطروح',   code: 'MUH', distanceKm: 410, driveMinutes: 300 },
  { id: 'ssh', name: 'مطار شرم الشيخ الدولي',      city: 'شرم الشيخ',    code: 'SSH', distanceKm: 520, driveMinutes: 390 },
  { id: 'hrg', name: 'مطار الغردقة الدولي',        city: 'الغردقة',      code: 'HRG', distanceKm: 480, driveMinutes: 360 },
  { id: 'lxr', name: 'مطار الأقصر الدولي',         city: 'الأقصر',       code: 'LXR', distanceKm: 700, driveMinutes: 480 },
  { id: 'asw', name: 'مطار أسوان الدولي',          city: 'أسوان',        code: 'ASW', distanceKm: 900, driveMinutes: 600 },
  { id: 'rmf', name: 'مطار مرسى علم الدولي',       city: 'مرسى علم',     code: 'RMF', distanceKm: 720, driveMinutes: 510 },
  { id: 'hmb', name: 'مطار سوهاج الدولي',          city: 'سوهاج',        code: 'HMB', distanceKm: 580, driveMinutes: 420 },
  { id: 'atz', name: 'مطار أسيوط',                 city: 'أسيوط',        code: 'ATZ', distanceKm: 620, driveMinutes: 450 },
];

export function getAirport(id: string): Airport | undefined {
  return AIRPORTS.find(a => a.id === id);
}

// ─── Vehicle types ────────────────────────────────────────────────────────────
export interface VehicleType {
  id: string;
  name: string;
  icon: string;
  desc: string;
  maxTravelers: number; // max seated passengers (excl. driver)
  freeBags: number;     // large bags included in base price
  maxBags: number;      // physical maximum large bags
  surcharge: number;    // EGP added on top of distance price
}

export const VEHICLE_TYPES: VehicleType[] = [
  {
    id: 'sedan', name: 'سيدان', icon: '🚗',
    desc: 'تويوتا / هيونداي',
    maxTravelers: 3, freeBags: 2, maxBags: 2, surcharge: 0,
  },
  {
    id: 'suv', name: 'SUV / كروز', icon: '🚙',
    desc: 'لاند كروزر / باترول',
    maxTravelers: 6, freeBags: 4, maxBags: 6, surcharge: 400,
  },
  {
    id: 'van', name: 'ميكروباص', icon: '🚐',
    desc: 'H1 / سبرينتر',
    maxTravelers: 10, freeBags: 8, maxBags: 20, surcharge: 800,
  },
];

// ─── Distance-based pricing 2026 ─────────────────────────────────────────────
// base 300 EGP + tiered per-km rate (driver goes & returns — fuel cost baked in)
// ≤150 km : 11 EGP/km  |  151-400 km : 10 EGP/km  |  401 km+ : 9 EGP/km
export const AIRPORT_BASE_FEE = 300;

export function priceForDistance(distanceKm: number): number {
  const TIERS: { upTo: number; rate: number }[] = [
    { upTo: 150,      rate: 11 },
    { upTo: 400,      rate: 10 },
    { upTo: Infinity, rate: 9  },
  ];
  let cost = AIRPORT_BASE_FEE;
  let covered = 0;
  for (const tier of TIERS) {
    if (distanceKm <= covered) break;
    const km = Math.min(distanceKm, tier.upTo) - covered;
    cost += km * tier.rate;
    covered = tier.upTo;
  }
  return Math.ceil(cost / 50) * 50;
}

// ─── Extra fees ───────────────────────────────────────────────────────────────
export const EXTRA_BAG_FEE      = 25;  // ج.م per bag over vehicle's free allowance
export const COMPANION_FEE      = 250; // ج.م per returning companion (round trip)
export const WAIT_PICKUP_FREE   = 15;  // free minutes waiting at pickup
export const WAIT_PICKUP_PER15  = 30;  // ج.م per each additional 15 min at pickup
export const WAIT_AIRPORT_FREE  = 30;  // free minutes at airport
export const WAIT_AIRPORT_PER30 = 40;  // ج.م per each additional 30 min at airport

// ─── Timing constants ─────────────────────────────────────────────────────────
export const CHECKIN_BUFFER = {
  domestic: 120,      // minutes before departure: must be at airport
  international: 180,
};
export const SAFETY_MARGIN = 20; // extra minutes added to drive time

// Arrivals: time needed after landing for immigration + baggage claim before
// the passenger reaches the arrivals hall exit.
export const ARRIVAL_BUFFER = {
  domestic: 20,
  international: 45,
};
// How early the driver should be waiting at the arrivals hall relative to
// the scheduled landing time (flights can land early).
export const DRIVER_ARRIVAL_BEFORE_LANDING = 15;

// Fixed reference point used to compute driving distance/time to any airport
// selected via the live Google Places search.
export const DAMIETTA_ORIGIN = { lat: 31.418, lng: 31.814 };
