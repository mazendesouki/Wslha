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

// Pricing constants
export const BASE_FARE    = 15;   // ج.م fixed flag-fall
export const RATE_PER_KM  = 7;    // ج.م per road-km
export const ROAD_FACTOR  = 1.35; // roads ~35% longer than straight line
export const MIN_FARE     = 20;   // ج.م minimum

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
