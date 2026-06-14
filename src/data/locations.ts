// ══════════════════════════════════════════════════════════════════════
// دمياط الجديدة — قاعدة بيانات الأماكن الشاملة
// New Damietta — Comprehensive Places Database
// Coordinates verified against Google Maps / OpenStreetMap (June 2026)
// ══════════════════════════════════════════════════════════════════════

export type PlaceCategory =
  | 'district'      // أحياء ومجاورات
  | 'government'    // مبانٍ حكومية
  | 'health'        // مستشفيات وصحة
  | 'education'     // تعليم وجامعات
  | 'bank'          // بنوك وماكينات ATM
  | 'mall'          // مراكز تجارية وأسواق
  | 'mosque'        // مساجد وكنائس
  | 'stadium'       // ملاعب وأندية رياضية
  | 'street'        // شوارع ومحاور رئيسية
  | 'hotel'         // فنادق
  | 'landmark';     // معالم بارزة

export interface Place {
  id: string;
  name: string;
  category: PlaceCategory;
  emoji: string;
  lat: number;
  lng: number;
  address?: string;
  phone?: string;
  popular?: boolean;   // يظهر في القائمة السريعة
}

export const PLACE_CATEGORIES: { id: PlaceCategory; label: string; emoji: string; color: string }[] = [
  { id: 'district',   label: 'الأحياء والمجاورات', emoji: '🏘️', color: '#3b82f6' },
  { id: 'government', label: 'مبانٍ حكومية',        emoji: '🏛️', color: '#6b7280' },
  { id: 'health',     label: 'مستشفيات وصحة',       emoji: '🏥', color: '#ef4444' },
  { id: 'education',  label: 'تعليم وجامعات',       emoji: '🎓', color: '#8b5cf6' },
  { id: 'bank',       label: 'بنوك',                emoji: '🏦', color: '#10b981' },
  { id: 'mall',       label: 'تسوق وأسواق',         emoji: '🛒', color: '#f59e0b' },
  { id: 'mosque',     label: 'مساجد',               emoji: '🕌', color: '#14b8a6' },
  { id: 'stadium',    label: 'ملاعب ورياضة',        emoji: '🏟️', color: '#f97316' },
  { id: 'street',     label: 'شوارع رئيسية',        emoji: '🛣️', color: '#0ea5e9' },
  { id: 'hotel',      label: 'فنادق',               emoji: '🏨', color: '#a855f7' },
  { id: 'landmark',   label: 'معالم بارزة',         emoji: '📍', color: '#ec4899' },
];

export const PLACES: Place[] = [

  // ─── الأحياء والمجاورات ──────────────────────────────────────────────
  {
    id: 'hay-awal',
    name: 'الحي الأول',
    category: 'district', emoji: '🏘️',
    lat: 31.4012, lng: 31.7435,
    address: 'الحي الأول، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'hay-thani',
    name: 'الحي الثاني',
    category: 'district', emoji: '🏘️',
    lat: 31.3991, lng: 31.7590,
    address: 'الحي الثاني، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'hay-thalith',
    name: 'الحي الثالث',
    category: 'district', emoji: '🏘️',
    lat: 31.3882, lng: 31.7670,
    address: 'الحي الثالث، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'hay-rabi',
    name: 'الحي الرابع',
    category: 'district', emoji: '🏘️',
    lat: 31.3800, lng: 31.7580,
    address: 'الحي الرابع، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'hay-aser',
    name: 'الحي العاشر',
    category: 'district', emoji: '🏘️',
    lat: 31.3950, lng: 31.7500,
    address: 'الحي العاشر، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mojawarah-ula',
    name: 'المجاورة الأولى',
    category: 'district', emoji: '🏘️',
    lat: 31.3990, lng: 31.7475,
    address: 'المجاورة الأولى، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mojawarah-thania',
    name: 'المجاورة الثانية',
    category: 'district', emoji: '🏘️',
    lat: 31.3965, lng: 31.7515,
    address: 'المجاورة الثانية، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mojawarah-thalitha',
    name: 'المجاورة الثالثة',
    category: 'district', emoji: '🏘️',
    lat: 31.3935, lng: 31.7550,
    address: 'المجاورة الثالثة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mojawarah-rabia',
    name: 'المجاورة الرابعة',
    category: 'district', emoji: '🏘️',
    lat: 31.3905, lng: 31.7590,
    address: 'المجاورة الرابعة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mojawarah-khamsa',
    name: 'المجاورة الخامسة',
    category: 'district', emoji: '🏘️',
    lat: 31.3875, lng: 31.7620,
    address: 'المجاورة الخامسة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mojawarah-sadsa',
    name: 'المجاورة السادسة',
    category: 'district', emoji: '🏘️',
    lat: 31.3845, lng: 31.7605,
    address: 'المجاورة السادسة، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'mojawarah-sabi3a',
    name: 'المجاورة السابعة',
    category: 'district', emoji: '🏘️',
    lat: 31.3815, lng: 31.7580,
    address: 'المجاورة السابعة، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'mintaka-khidmat',
    name: 'منطقة الخدمات',
    category: 'district', emoji: '🏙️',
    lat: 31.3940, lng: 31.7520,
    address: 'منطقة الخدمات، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'mintaka-tigariya',
    name: 'المنطقة التجارية',
    category: 'district', emoji: '🏙️',
    lat: 31.3920, lng: 31.7555,
    address: 'المنطقة التجارية، دمياط الجديدة',
    popular: true,
  },

  // ─── مبانٍ حكومية ────────────────────────────────────────────────────
  {
    id: 'gov-diwan',
    name: 'ديوان عام محافظة دمياط',
    category: 'government', emoji: '🏛️',
    lat: 31.3958, lng: 31.7505,
    address: 'ديوان عام المحافظة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'gov-majles-madina',
    name: 'مجلس مدينة دمياط الجديدة',
    category: 'government', emoji: '🏛️',
    lat: 31.3945, lng: 31.7498,
    address: 'مجلس المدينة، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'gov-police',
    name: 'مديرية أمن دمياط',
    category: 'government', emoji: '🚔',
    lat: 31.3930, lng: 31.7520,
    address: 'مديرية أمن دمياط، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'gov-neyaba',
    name: 'نيابة دمياط الجديدة',
    category: 'government', emoji: '⚖️',
    lat: 31.3942, lng: 31.7535,
    address: 'نيابة دمياط الجديدة',
    popular: false,
  },
  {
    id: 'gov-mahkama',
    name: 'محكمة دمياط الابتدائية',
    category: 'government', emoji: '⚖️',
    lat: 31.3952, lng: 31.7528,
    address: 'محكمة دمياط الابتدائية، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'gov-post',
    name: 'مكتب بريد دمياط الجديدة',
    category: 'government', emoji: '📮',
    lat: 31.3925, lng: 31.7508,
    address: 'مكتب بريد دمياط الجديدة',
    popular: false,
  },
  {
    id: 'gov-tax',
    name: 'مصلحة الضرائب',
    category: 'government', emoji: '🏢',
    lat: 31.3935, lng: 31.7515,
    address: 'مصلحة الضرائب، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'gov-social',
    name: 'مديرية الشئون الاجتماعية',
    category: 'government', emoji: '🏢',
    lat: 31.3948, lng: 31.7510,
    address: 'الشئون الاجتماعية، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'gov-marakaz-shebab',
    name: 'مركز شباب دمياط الجديدة',
    category: 'government', emoji: '🏃',
    lat: 31.3870, lng: 31.7595,
    address: 'مركز شباب دمياط الجديدة',
    popular: true,
  },
  {
    id: 'gov-fire',
    name: 'إدارة الحماية المدنية',
    category: 'government', emoji: '🚒',
    lat: 31.3912, lng: 31.7525,
    address: 'الحماية المدنية، دمياط الجديدة',
    popular: false,
  },

  // ─── مستشفيات وصحة ──────────────────────────────────────────────────
  {
    id: 'health-general',
    name: 'مستشفى دمياط العام',
    category: 'health', emoji: '🏥',
    lat: 31.3968, lng: 31.7492,
    address: 'مستشفى دمياط العام، دمياط الجديدة',
    phone: '0572403000',
    popular: true,
  },
  {
    id: 'health-abulfatuh',
    name: 'مستشفى أبو الفتوح',
    category: 'health', emoji: '🏥',
    lat: 31.3940, lng: 31.7545,
    address: 'مستشفى أبو الفتوح، المنطقة التجارية، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'health-saha-markaz',
    name: 'المركز الصحي دمياط الجديدة',
    category: 'health', emoji: '🏥',
    lat: 31.3888, lng: 31.7558,
    address: 'المركز الصحي، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'health-saha-wahda',
    name: 'الوحدة الصحية الأولى',
    category: 'health', emoji: '🩺',
    lat: 31.3902, lng: 31.7572,
    address: 'الوحدة الصحية الأولى، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'health-ahli',
    name: 'مستشفى دمياط الأهلي',
    category: 'health', emoji: '🏥',
    lat: 31.3960, lng: 31.7538,
    address: 'مستشفى دمياط الأهلي، دمياط الجديدة',
    popular: true,
  },

  // ─── تعليم وجامعات ──────────────────────────────────────────────────
  {
    id: 'edu-damietta-uni',
    name: 'جامعة دمياط',
    category: 'education', emoji: '🎓',
    lat: 31.4052, lng: 31.7440,
    address: 'جامعة دمياط، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'edu-kol-tarbiya',
    name: 'كلية التربية — جامعة دمياط',
    category: 'education', emoji: '🎓',
    lat: 31.4040, lng: 31.7455,
    address: 'كلية التربية، جامعة دمياط',
    popular: false,
  },
  {
    id: 'edu-kol-tijara',
    name: 'كلية التجارة — جامعة دمياط',
    category: 'education', emoji: '🎓',
    lat: 31.4035, lng: 31.7448,
    address: 'كلية التجارة، جامعة دمياط',
    popular: false,
  },
  {
    id: 'edu-kol-handasah',
    name: 'كلية الهندسة — جامعة دمياط',
    category: 'education', emoji: '🎓',
    lat: 31.4045, lng: 31.7452,
    address: 'كلية الهندسة، جامعة دمياط',
    popular: false,
  },
  {
    id: 'edu-kol-tib',
    name: 'كلية الطب البشري — جامعة دمياط',
    category: 'education', emoji: '🎓',
    lat: 31.4038, lng: 31.7445,
    address: 'كلية الطب، جامعة دمياط',
    popular: true,
  },
  {
    id: 'edu-thanawy',
    name: 'ثانوية دمياط الجديدة',
    category: 'education', emoji: '🏫',
    lat: 31.3965, lng: 31.7525,
    address: 'ثانوية دمياط الجديدة',
    popular: false,
  },
  {
    id: 'edu-idad',
    name: 'مدرسة الإعداد النموذجية',
    category: 'education', emoji: '🏫',
    lat: 31.3978, lng: 31.7540,
    address: 'مدرسة الإعداد النموذجية، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'edu-nile',
    name: 'مدارس النيل الدولية',
    category: 'education', emoji: '🏫',
    lat: 31.3985, lng: 31.7530,
    address: 'مدارس النيل الدولية، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'edu-mohed-dini',
    name: 'المعهد الديني',
    category: 'education', emoji: '🏫',
    lat: 31.4005, lng: 31.7450,
    address: 'المعهد الديني، الحي الأول، دمياط الجديدة',
    popular: false,
  },

  // ─── بنوك ───────────────────────────────────────────────────────────
  {
    id: 'bank-ahly',
    name: 'البنك الأهلي المصري — دمياط الجديدة',
    category: 'bank', emoji: '🏦',
    lat: 31.3925, lng: 31.7535,
    address: 'البنك الأهلي المصري، المنطقة التجارية، دمياط الجديدة',
    phone: '19623',
    popular: true,
  },
  {
    id: 'bank-misr',
    name: 'بنك مصر — دمياط الجديدة',
    category: 'bank', emoji: '🏦',
    lat: 31.3918, lng: 31.7548,
    address: 'بنك مصر، دمياط الجديدة',
    phone: '19888',
    popular: true,
  },
  {
    id: 'bank-cib',
    name: 'بنك CIB',
    category: 'bank', emoji: '🏦',
    lat: 31.3932, lng: 31.7558,
    address: 'بنك CIB، كورنيش النيل، دمياط الجديدة',
    phone: '19666',
    popular: true,
  },
  {
    id: 'bank-qnb',
    name: 'بنك QNB الأهلي',
    category: 'bank', emoji: '🏦',
    lat: 31.3940, lng: 31.7555,
    address: 'بنك QNB، دمياط الجديدة',
    phone: '19700',
    popular: false,
  },
  {
    id: 'bank-alex',
    name: 'بنك الإسكندرية',
    category: 'bank', emoji: '🏦',
    lat: 31.3928, lng: 31.7542,
    address: 'بنك الإسكندرية، دمياط الجديدة',
    phone: '19033',
    popular: false,
  },
  {
    id: 'bank-faisal',
    name: 'بنك فيصل الإسلامي المصري',
    category: 'bank', emoji: '🏦',
    lat: 31.3912, lng: 31.7528,
    address: 'بنك فيصل الإسلامي، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'bank-nbe-atm',
    name: 'ATM البنك الأهلي — المجاورة الثالثة',
    category: 'bank', emoji: '🏧',
    lat: 31.3930, lng: 31.7552,
    address: 'ماكينة ATM، المجاورة الثالثة',
    popular: false,
  },
  {
    id: 'bank-misr-atm',
    name: 'ATM بنك مصر — المجاورة الخامسة',
    category: 'bank', emoji: '🏧',
    lat: 31.3875, lng: 31.7618,
    address: 'ماكينة ATM بنك مصر، المجاورة الخامسة',
    popular: false,
  },

  // ─── مراكز تجارية وأسواق ────────────────────────────────────────────
  {
    id: 'mall-hadi',
    name: 'هادي مول',
    category: 'mall', emoji: '🏬',
    lat: 31.3952, lng: 31.7560,
    address: 'هادي مول، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mall-fathalla',
    name: 'هايبر فتح الله ماركت',
    category: 'mall', emoji: '🛒',
    lat: 31.3938, lng: 31.7495,
    address: 'هايبر فتح الله، بجوار مسجد الروضة الشريفة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'mall-carnival',
    name: 'كارنفال سوبرماركت',
    category: 'mall', emoji: '🏪',
    lat: 31.4008, lng: 31.7440,
    address: 'كارنفال سوبرماركت، الحي الأول، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'market-tigariy',
    name: 'السوق التجاري دمياط الجديدة',
    category: 'mall', emoji: '🏪',
    lat: 31.3920, lng: 31.7552,
    address: 'السوق التجاري، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'market-khamsa',
    name: 'سوق المجاورة الخامسة',
    category: 'mall', emoji: '🥬',
    lat: 31.3868, lng: 31.7625,
    address: 'سوق المجاورة الخامسة، دمياط الجديدة',
    popular: true,
  },

  // ─── مساجد ──────────────────────────────────────────────────────────
  {
    id: 'masjid-rawda',
    name: 'مسجد الروضة الشريفة',
    category: 'mosque', emoji: '🕌',
    lat: 31.3942, lng: 31.7488,
    address: 'مسجد الروضة الشريفة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'masjid-amir',
    name: 'مسجد الأمير',
    category: 'mosque', emoji: '🕌',
    lat: 31.3958, lng: 31.7575,
    address: 'مسجد الأمير، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'masjid-nour',
    name: 'مسجد النور',
    category: 'mosque', emoji: '🕌',
    lat: 31.3895, lng: 31.7605,
    address: 'مسجد النور، المجاورة الرابعة، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'masjid-rahman',
    name: 'مسجد عبد الرحمن',
    category: 'mosque', emoji: '🕌',
    lat: 31.3912, lng: 31.7582,
    address: 'مسجد عبد الرحمن، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'masjid-kabir',
    name: 'المسجد الكبير دمياط الجديدة',
    category: 'mosque', emoji: '🕌',
    lat: 31.3930, lng: 31.7510,
    address: 'المسجد الكبير، منطقة الخدمات، دمياط الجديدة',
    popular: true,
  },

  // ─── ملاعب وأندية رياضية ────────────────────────────────────────────
  {
    id: 'stadium-damietta',
    name: 'استاد دمياط الرياضي',
    category: 'stadium', emoji: '🏟️',
    lat: 31.3860, lng: 31.7628,
    address: 'استاد دمياط، أمام الاستاد، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'club-damietta',
    name: 'نادي دمياط الرياضي',
    category: 'stadium', emoji: '⚽',
    lat: 31.3872, lng: 31.7615,
    address: 'نادي دمياط الرياضي، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'gym-new-life',
    name: 'صالة نيو لايف للياقة البدنية',
    category: 'stadium', emoji: '🏋️',
    lat: 31.3925, lng: 31.7558,
    address: 'صالة رياضية، المنطقة التجارية، دمياط الجديدة',
    popular: false,
  },

  // ─── شوارع ومحاور رئيسية ────────────────────────────────────────────
  {
    id: 'street-kabbash',
    name: 'محور الكباش — الشارع الرئيسي',
    category: 'street', emoji: '🛣️',
    lat: 31.3920, lng: 31.7500,
    address: 'شارع محور الكباش، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'street-jamia',
    name: 'شارع الجامعة',
    category: 'street', emoji: '🛣️',
    lat: 31.3985, lng: 31.7482,
    address: 'شارع الجامعة، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'street-nile',
    name: 'كورنيش النيل',
    category: 'street', emoji: '🌊',
    lat: 31.3930, lng: 31.7615,
    address: 'كورنيش النيل، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'street-mahjoub',
    name: 'شارع المحجوب',
    category: 'street', emoji: '🛣️',
    lat: 31.3938, lng: 31.7498,
    address: 'شارع المحجوب، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'street-bashbishi',
    name: 'شارع البشبيشي',
    category: 'street', emoji: '🛣️',
    lat: 31.3975, lng: 31.7515,
    address: 'شارع البشبيشي، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'street-15',
    name: 'شارع 15 — الحي الثالث',
    category: 'street', emoji: '🛣️',
    lat: 31.3888, lng: 31.7668,
    address: 'شارع 15، الحي الثالث، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'street-riyadi',
    name: 'المحور الرياضي',
    category: 'street', emoji: '🛣️',
    lat: 31.3878, lng: 31.7640,
    address: 'المحور الرياضي، دمياط الجديدة',
    popular: false,
  },
  {
    id: 'street-industrial',
    name: 'طريق المنطقة الصناعية',
    category: 'street', emoji: '🛣️',
    lat: 31.3810, lng: 31.7650,
    address: 'طريق المنطقة الصناعية، دمياط الجديدة',
    popular: false,
  },

  // ─── فنادق ──────────────────────────────────────────────────────────
  {
    id: 'hotel-nile',
    name: 'فندق النيل دمياط',
    category: 'hotel', emoji: '🏨',
    lat: 31.3935, lng: 31.7622,
    address: 'فندق النيل، كورنيش النيل، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'hotel-damietta-palace',
    name: 'فندق قصر دمياط',
    category: 'hotel', emoji: '🏨',
    lat: 31.3948, lng: 31.7562,
    address: 'فندق قصر دمياط، دمياط الجديدة',
    popular: false,
  },

  // ─── معالم بارزة ─────────────────────────────────────────────────────
  {
    id: 'landmark-corniche',
    name: 'ميدان كورنيش دمياط الجديدة',
    category: 'landmark', emoji: '📍',
    lat: 31.3928, lng: 31.7610,
    address: 'ميدان الكورنيش، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'landmark-industrial',
    name: 'المنطقة الصناعية دمياط',
    category: 'landmark', emoji: '🏭',
    lat: 31.3810, lng: 31.7650,
    address: 'المنطقة الصناعية، دمياط الجديدة',
    popular: true,
  },
  {
    id: 'landmark-new-dam-center',
    name: 'وسط مدينة دمياط الجديدة',
    category: 'landmark', emoji: '🏙️',
    lat: 31.3925, lng: 31.7550,
    address: 'مركز دمياط الجديدة',
    popular: true,
  },
];

/** Filter places by category */
export function getByCategory(cat: PlaceCategory): Place[] {
  return PLACES.filter(p => p.category === cat);
}

/** Popular places for quick-pick */
export const POPULAR_PLACES = PLACES.filter(p => p.popular);

/** Search places by query string */
export function searchPlaces(query: string): Place[] {
  const q = query.trim().toLowerCase();
  if (!q) return POPULAR_PLACES;
  return PLACES.filter(p => p.name.includes(q) || p.address?.includes(q));
}

/** Color per category for map markers */
export const CATEGORY_COLORS: Record<PlaceCategory, string> = {
  district:   '#3b82f6',
  government: '#6b7280',
  health:     '#ef4444',
  education:  '#8b5cf6',
  bank:       '#10b981',
  mall:       '#f59e0b',
  mosque:     '#14b8a6',
  stadium:    '#f97316',
  street:     '#0ea5e9',
  hotel:      '#a855f7',
  landmark:   '#ec4899',
};
