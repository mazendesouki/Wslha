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

// ─── Vehicle catalog: make/model with per-km operating rate ──────────────────
// ratePerKm = fuel (round trip) + maintenance/depreciation + driver profit,
// per km of the customer-facing distance. Tuned per model class June 2026.
export interface VehicleModel {
  id: string;
  category: 'sedan' | 'suv' | 'van';
  name: string;       // الماركة والموديل
  yearFrom: number;
  yearTo: number;
  ratePerKm: number;  // EGP per km (base, before year adjustment)
}

export const VEHICLE_MODELS: VehicleModel[] = [
  // سيدان
  { id: 'corolla',  category: 'sedan', name: 'تويوتا كورولا',    yearFrom: 2016, yearTo: 2026, ratePerKm: 10.5 },
  { id: 'elantra',  category: 'sedan', name: 'هيونداي إلنترا',   yearFrom: 2016, yearTo: 2026, ratePerKm: 10   },
  { id: 'cerato',   category: 'sedan', name: 'كيا سيراتو',       yearFrom: 2016, yearTo: 2026, ratePerKm: 10   },
  { id: 'sunny',    category: 'sedan', name: 'نيسان صني',        yearFrom: 2016, yearTo: 2026, ratePerKm: 9    },
  { id: 'logan',    category: 'sedan', name: 'رينو لوجان',       yearFrom: 2016, yearTo: 2026, ratePerKm: 9    },
  // SUV
  { id: 'landcruiser', category: 'suv', name: 'تويوتا لاند كروزر', yearFrom: 2016, yearTo: 2026, ratePerKm: 16   },
  { id: 'patrol',      category: 'suv', name: 'نيسان باترول',      yearFrom: 2016, yearTo: 2026, ratePerKm: 15.5 },
  { id: 'tucson',      category: 'suv', name: 'هيونداي توسان',     yearFrom: 2016, yearTo: 2026, ratePerKm: 13   },
  { id: 'sportage',    category: 'suv', name: 'كيا سبورتاج',       yearFrom: 2016, yearTo: 2026, ratePerKm: 13   },
  { id: 'xtrail',      category: 'suv', name: 'نيسان إكس تريل',    yearFrom: 2016, yearTo: 2026, ratePerKm: 13.5 },
  // ميكروباص
  { id: 'h1',       category: 'van', name: 'هيونداي H1',        yearFrom: 2016, yearTo: 2026, ratePerKm: 14   },
  { id: 'hiace',    category: 'van', name: 'تويوتا هاي إيس',    yearFrom: 2016, yearTo: 2026, ratePerKm: 13.5 },
  { id: 'sprinter', category: 'van', name: 'مرسيدس سبرينتر',    yearFrom: 2016, yearTo: 2026, ratePerKm: 16   },
];

// Year adjustment: newer cars cost more to run (higher depreciation & comfort
// premium); older cars run cheaper but with slightly higher maintenance —
// net effect tuned per band.
export function yearMultiplier(year: number): number {
  if (year >= 2024) return 1.15; // موديل حديث — راحة وضمان أعلى
  if (year >= 2020) return 1.0;  // المعيار
  return 0.9;                    // موديل أقدم — سعر اقتصادي
}

// Fare for a specific model+year over a given distance.
export function fareForVehicle(distanceKm: number, model: VehicleModel, year: number): number {
  const raw = AIRPORT_BASE_FEE + distanceKm * model.ratePerKm * yearMultiplier(year);
  return Math.ceil(raw / 50) * 50;
}

// ─── Local-ride flexible meter ────────────────────────────────────────────────
// fare = ceil( max( (25 + tieredKmCost × modelRate×1.2×yearMult) × zoneFactor
//                    + zoneSurcharge, 35) / 5 ) × 5
// Distance tiers (like a real meter): first 3 km ×1.15, 3–10 km ×1.0, >10 km ×0.9.
// ⚠️ Any change here must be mirrored in db/rides-vehicle-pricing.sql.
export const RIDE_BASE_FARE   = 25;
export const RIDE_MIN_FARE    = 35;
export const RIDE_CITY_FACTOR = 1.2;
export const RIDE_TIERS = { t1Km: 3, t1Mult: 1.15, t2Km: 10, t2Mult: 1.0, t3Mult: 0.9 };

// Destination zones — matched by keywords in the destination name.
export interface FareZone { id: string; label: string; factor: number; surcharge: number; keywords: string[]; }
export const FARE_ZONES: FareZone[] = [
  { id: 'rasbar',     label: 'رأس البر (مصيف)',          factor: 1.15, surcharge: 10, keywords: ['رأس البر', 'راس البر'] },
  { id: 'remote',     label: 'أطراف المحافظة',            factor: 1.10, surcharge: 15, keywords: ['فارسكور', 'الزرقا', 'كفر البطيخ', 'الروضة', 'كفر سعد', 'ميت أبو غالب', 'عزبة البرج', 'الرحامنة', 'السرو'] },
  { id: 'industrial', label: 'المنطقة الصناعية والميناء', factor: 1.05, surcharge: 10, keywords: ['الصناعية', 'ميناء', 'الميناء', 'شطا'] },
];
export const STANDARD_ZONE: FareZone = { id: 'standard', label: 'داخل المدينة', factor: 1, surcharge: 0, keywords: [] };

export function resolveZone(destName: string | null | undefined): FareZone {
  if (!destName) return STANDARD_ZONE;
  for (const z of FARE_ZONES) {
    if (z.keywords.some(k => destName.includes(k))) return z;
  }
  return STANDARD_ZONE;
}

// Tiered distance cost in "rate units" (multiply by the effective EGP/km rate).
export function tieredKm(km: number): number {
  const t1 = Math.min(km, RIDE_TIERS.t1Km);
  const t2 = Math.min(Math.max(km - RIDE_TIERS.t1Km, 0), RIDE_TIERS.t2Km - RIDE_TIERS.t1Km);
  const t3 = Math.max(km - RIDE_TIERS.t2Km, 0);
  return t1 * RIDE_TIERS.t1Mult + t2 * RIDE_TIERS.t2Mult + t3 * RIDE_TIERS.t3Mult;
}

export function meterFare(km: number, model: VehicleModel, year: number, zone: FareZone): number {
  const rate = model.ratePerKm * RIDE_CITY_FACTOR * yearMultiplier(year);
  const raw  = (RIDE_BASE_FARE + tieredKm(km) * rate) * zone.factor + zone.surcharge;
  return Math.ceil(Math.max(raw, RIDE_MIN_FARE) / 5) * 5;
}

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
export const COMPANION_FEE      = 500; // ج.م per returning companion (round trip)
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
