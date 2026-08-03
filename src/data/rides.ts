export interface Area {
  id: string;
  name: string;
  lat: number;
  lng: number;
}

export const AREAS: Area[] = [
  { id: 'center',           name: 'وسط دمياط',       lat: 31.418, lng: 31.814 },
  { id: 'new-damietta',     name: 'دمياط الجديدة',    lat: 31.392, lng: 31.755 },
  { id: 'industrial',       name: 'المنطقة الصناعية', lat: 31.381, lng: 31.765 },
  { id: 'sheikh-zaghloul',  name: 'الشيخ زغلول',      lat: 31.436, lng: 31.762 },
  { id: 'kafr-saad',        name: 'كفر سعد',           lat: 31.402, lng: 31.732 },
  { id: 'ras-el-bar',       name: 'رأس البر',          lat: 31.490, lng: 31.829 },
  { id: 'izbet-elburg',     name: 'عزبة البرج',        lat: 31.496, lng: 31.843 },
  { id: 'el-saro',          name: 'السرو',             lat: 31.356, lng: 31.810 },
  { id: 'meet-abu-ghalib',  name: 'ميت أبو غالب',     lat: 31.365, lng: 31.864 },
  { id: 'faraskur',         name: 'فارسكور',           lat: 31.328, lng: 31.672 },
  { id: 'zarqa',            name: 'الزرقا',            lat: 31.312, lng: 31.874 },
  { id: 'el-riyad',         name: 'الرياض',            lat: 31.297, lng: 31.787 },
  { id: 'kafr-batikh',      name: 'كفر البطيخ',        lat: 31.270, lng: 31.933 },
];

export interface Airport {
  id: string;
  name: string;
  lat: number;
  lng: number;
  flatFare: number;    // EGP — سعر ثابت من محافظة دمياط
  driveMins: number;   // متوسط وقت القيادة من وسط دمياط
}

// ─── Airport flat fares from Damietta (updated June 2026) ─────────────────────
// Calculated via tiered formula: 300 base + 11/km (≤150) + 10/km (151-400) + 9/km (400+)
export const AIRPORTS: Airport[] = [
  { id: 'port-said',  name: 'مطار بورسعيد',              lat: 31.282, lng: 32.236, flatFare: 1250, driveMins: 90  },
  { id: 'cairo',      name: 'مطار القاهرة الدولي ✈️',    lat: 30.122, lng: 31.406, flatFare: 2450, driveMins: 200 },
  { id: 'alex',       name: 'مطار برج العرب (إسكندرية)', lat: 30.917, lng: 29.696, flatFare: 2950, driveMins: 230 },
  { id: 'sharm',      name: 'مطار شرم الشيخ',             lat: 27.977, lng: 34.395, flatFare: 5550, driveMins: 310 },
  { id: 'hurghada',   name: 'مطار الغردقة',               lat: 27.178, lng: 33.800, flatFare: 5200, driveMins: 360 },
  { id: 'luxor',      name: 'مطار الأقصر',                lat: 25.671, lng: 32.706, flatFare: 7150, driveMins: 420 },
];

// ─── Local rides pricing (updated June 2026 — ارتفاع أسعار الوقود) ──────────
export const BASE_FARE    = 25;   // ج.م — عداد الانطلاق
export const RATE_PER_KM  = 12;   // ج.م / كم
export const ROAD_FACTOR  = 1.35; // طرق مصرية ~35% أطول من الخط المستقيم
export const MIN_FARE     = 40;   // ج.م — الحد الأدنى للرحلة

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function fareForDistance(straightKm: number): number {
  const road = straightKm * ROAD_FACTOR;
  const raw  = BASE_FARE + road * RATE_PER_KM;
  return Math.ceil(Math.max(raw, MIN_FARE) / 5) * 5;
}

export function etaMinutes(straightKm: number): number {
  return Math.ceil((straightKm * ROAD_FACTOR) / 40 * 60); // 40 km/h avg
}
