// Egyptian airports served from Damietta governorate.
// Distance/drive-time are approximate road estimates from Damietta city.
// Price is distance-based (see priceFor()).

export interface Airport {
  id: string;
  name: string;
  city: string;
  code: string;       // IATA
  distanceKm: number; // road distance from Damietta
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

// Distance-based pricing: base fee + per-km rate, rounded up to nearest 10 EGP.
export const AIRPORT_BASE_FEE = 150;   // ج.م
export const AIRPORT_RATE_PER_KM = 6;  // ج.م / كم

export function priceForDistance(distanceKm: number): number {
  const raw = AIRPORT_BASE_FEE + distanceKm * AIRPORT_RATE_PER_KM;
  return Math.ceil(raw / 10) * 10;
}

export function getAirport(id: string): Airport | undefined {
  return AIRPORTS.find(a => a.id === id);
}

// Recommended check-in buffer (minutes before departure to BE at the airport).
export const CHECKIN_BUFFER = {
  domestic: 120,       // محلية
  international: 180,   // دولية
};

// Extra safety margin added to the drive so the car leaves a bit early.
export const SAFETY_MARGIN = 20; // minutes
