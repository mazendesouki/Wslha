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

// ─── Vehicle catalog: registered make/model available for booking ────────────
// السعر بالكيلومتر ما عاد مربوط بالموديل نفسه — بيتحدد حسب فئة السيارة
// (سيدان/SUV/فان) ونوع الرحلة (داخلي/خارجي/مطار) عبر TRIP_RATES تحت.
// القائمة هنا بتمثّل السيارات المسجّلة فعليًا في النظام (نفس الكتالوج
// المستخدم في تسجيل السائقين) — العميل يختار موديل وسنة من المسجّل فقط.
export interface VehicleModel {
  id: string;
  category: 'sedan' | 'suv' | 'van';
  name: string;       // الماركة والموديل
  yearFrom: number;
  yearTo: number;
}

export const VEHICLE_MODELS: VehicleModel[] = [
  // سيدان — اقتصادي
  { id: 'logan',      category: 'sedan', name: 'رينو لوجان',        yearFrom: 2015, yearTo: 2027 },
  { id: 'sunny',      category: 'sedan', name: 'نيسان صني',         yearFrom: 2015, yearTo: 2027 },
  { id: 'optra',      category: 'sedan', name: 'شيفروليه أوبترا',   yearFrom: 2015, yearTo: 2027 },
  { id: 'peugeot301', category: 'sedan', name: 'بيجو 301',          yearFrom: 2016, yearTo: 2027 },
  { id: 'fiattipo',   category: 'sedan', name: 'فيات تيبو',         yearFrom: 2018, yearTo: 2027 },
  // سيدان — عائلي/متوسط
  { id: 'corolla',    category: 'sedan', name: 'تويوتا كورولا',     yearFrom: 2015, yearTo: 2027 },
  { id: 'elantra',    category: 'sedan', name: 'هيونداي إلنترا',    yearFrom: 2015, yearTo: 2027 },
  { id: 'cerato',     category: 'sedan', name: 'كيا سيراتو',        yearFrom: 2015, yearTo: 2027 },
  { id: 'mg5',        category: 'sedan', name: 'إم جي 5',           yearFrom: 2021, yearTo: 2027 },
  { id: 'octavia',    category: 'sedan', name: 'سكودا أوكتافيا',    yearFrom: 2019, yearTo: 2027 },
  // سيدان — فاخر
  { id: 'bmw3',       category: 'sedan', name: 'بي إم دبليو الفئة 3', yearFrom: 2018, yearTo: 2027 },
  { id: 'mercc',      category: 'sedan', name: 'مرسيدس الفئة C',      yearFrom: 2018, yearTo: 2027 },
  // SUV — مدمج/كروس أوفر
  { id: 'mgzs',       category: 'suv', name: 'إم جي ZS',           yearFrom: 2020, yearTo: 2027 },
  { id: 'creta',      category: 'suv', name: 'هيونداي كريتا',       yearFrom: 2020, yearTo: 2027 },
  { id: 'tucson',     category: 'suv', name: 'هيونداي توسان',       yearFrom: 2015, yearTo: 2027 },
  { id: 'sportage',   category: 'suv', name: 'كيا سبورتاج',         yearFrom: 2015, yearTo: 2027 },
  // SUV — متوسط/كبير
  { id: 'xtrail',     category: 'suv', name: 'نيسان إكس تريل',      yearFrom: 2015, yearTo: 2027 },
  { id: 'tiggo8',     category: 'suv', name: 'شيري تيجو 8',         yearFrom: 2021, yearTo: 2027 },
  { id: 'compass',    category: 'suv', name: 'جيب كومباس',          yearFrom: 2019, yearTo: 2027 },
  // SUV — فل سايز/فاخر
  { id: 'landcruiser', category: 'suv', name: 'تويوتا لاند كروزر',  yearFrom: 2015, yearTo: 2027 },
  { id: 'patrol',      category: 'suv', name: 'نيسان باترول',       yearFrom: 2015, yearTo: 2027 },
  { id: 'pajero',      category: 'suv', name: 'ميتسوبيشي باجيرو',   yearFrom: 2015, yearTo: 2027 },
  { id: 'grandcherokee', category: 'suv', name: 'جيب جراند شيروكي', yearFrom: 2018, yearTo: 2027 },
  // ميكروباص / فان
  { id: 'xpander',    category: 'van', name: 'ميتسوبيشي إكسباندر', yearFrom: 2019, yearTo: 2027 },
  { id: 'hiace',      category: 'van', name: 'تويوتا هاي إيس',      yearFrom: 2015, yearTo: 2027 },
  { id: 'h1',         category: 'van', name: 'هيونداي H1',          yearFrom: 2015, yearTo: 2027 },
  { id: 'carnival',   category: 'van', name: 'كيا كارنيفال',        yearFrom: 2019, yearTo: 2027 },
  { id: 'traveller',  category: 'van', name: 'بيجو ترافيلر',        yearFrom: 2018, yearTo: 2027 },
  { id: 'sprinter',   category: 'van', name: 'مرسيدس سبرينتر',      yearFrom: 2015, yearTo: 2027 },
];

// Year adjustment: continuous per-year gradient (not fixed bands), so each model
// year — including the newest 2026/2027 releases — gets its own distinct rate.
// 2021 = baseline (×1.0); +3.5% per newer year, −3.5% per older year, clamped.
// ⚠️ Any change here must be mirrored in db/rides-vehicle-pricing.sql (v_mult).
export function yearMultiplier(year: number): number {
  const raw = 1 + (year - 2021) * 0.035;
  return Math.round(Math.min(1.35, Math.max(0.8, raw)) * 1000) / 1000;
}

// ─── سعر الكيلومتر حسب نوع الرحلة وفئة السيارة ────────────────────────────────
// سعر ثابت للكيلومتر لكل نوع رحلة، أساسه السيدان، وSUV/الفان أعلى بنسبة ثابتة
// (+30% / +40%) — بدل السعر المتفاوت لكل موديل سابقًا. سعر السيدان الأساسي:
//   داخلي (داخل دمياط)         8  ج.م/كم
//   خارجي (خارج محافظة دمياط)  7  ج.م/كم
//   مطار                       12 ج.م/كم
// ⚠️ أي تعديل هنا لازم يتطابق مع db/rides-vehicle-pricing.sql.
export type TripType = 'local' | 'external' | 'airport';
const SUV_MULT = 1.3;
const VAN_MULT = 1.4;
export const TRIP_RATES: Record<TripType, Record<'sedan' | 'suv' | 'van', number>> = {
  local:    { sedan: 8, suv: Math.round(8 * SUV_MULT * 10) / 10, van: Math.round(8 * VAN_MULT * 10) / 10 },
  external: { sedan: 7, suv: Math.round(7 * SUV_MULT * 10) / 10, van: Math.round(7 * VAN_MULT * 10) / 10 },
  airport:  { sedan: 12, suv: Math.round(12 * SUV_MULT * 10) / 10, van: Math.round(12 * VAN_MULT * 10) / 10 },
};

// سعر الكيلومتر الفعّال لموديل بعينه في نوع رحلة معيّن، بعد تعديل سنة الصنع.
export function ratePerKmFor(tripType: TripType, model: VehicleModel, year: number): number {
  return TRIP_RATES[tripType][model.category] * yearMultiplier(year);
}

// Fare for a specific model+year over a given distance (airport transfer).
export function fareForVehicle(distanceKm: number, model: VehicleModel, year: number): number {
  const raw = AIRPORT_BASE_FEE + distanceKm * ratePerKmFor('airport', model, year);
  return Math.ceil(raw / 50) * 50;
}

// ─── Local-ride flexible meter ────────────────────────────────────────────────
// fare = ceil( max( (25 + tieredKmCost × rate) × zoneFactor + zoneSurcharge, 35) / 5 ) × 5
// Distance tiers (like a real meter): first 3 km ×1.15, 3–10 km ×1.0, >10 km ×0.9.
// ⚠️ Any change here must be mirrored in db/rides-vehicle-pricing.sql.
export const RIDE_BASE_FARE   = 25;
export const RIDE_MIN_FARE    = 35;
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
  const rate = ratePerKmFor('local', model, year);
  const raw  = (RIDE_BASE_FARE + tieredKm(km) * rate) * zone.factor + zone.surcharge;
  return Math.ceil(Math.max(raw, RIDE_MIN_FARE) / 5) * 5;
}

// ─── رحلات خارجية (خارج محافظة دمياط) — خدمة منفصلة ───────────────────────────
// عداد أبسط: رسم أساسي + مسافة × سعر الخارجي (بدون تدرّج كيلومترات أو مناطق —
// كله برّه الحدود بنفس السعر). ⚠️ يطابق db/rides-vehicle-pricing.sql.
export const EXTERNAL_BASE_FARE = 50;
export const EXTERNAL_MIN_FARE  = 150;

export function externalFare(km: number, model: VehicleModel, year: number): number {
  const rate = ratePerKmFor('external', model, year);
  const raw  = EXTERNAL_BASE_FARE + km * rate;
  return Math.ceil(Math.max(raw, EXTERNAL_MIN_FARE) / 5) * 5;
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
