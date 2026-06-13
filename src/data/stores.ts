// Real merchants in Damietta governorate — primarily New Damietta (دمياط الجديدة)
// Prices in EGP — updated for 2026 Egyptian market rates
// This static data is used at build time for SSG + as Supabase seed.

export interface Product {
  id: string;
  name: string;
  desc?: string;
  price: number;
  emoji: string;
}

export interface MenuSection {
  section: string;
  items: Product[];
}

export interface Store {
  id: string;
  name: string;
  category: string;
  categoryId: string;
  emoji: string;
  area: string;
  phone?: string;
  address?: string;
  rating: number;
  reviews: number;
  deliveryTime: string;
  deliveryFee: number;
  minOrder: number;
  tagline: string;
  menu: MenuSection[];
}

export interface Category {
  id: string;
  label: string;
  emoji: string;
}

export const CATEGORIES: Category[] = [
  { id: 'all',        label: 'الكل',          emoji: '🛍️' },
  { id: 'restaurant', label: 'مطاعم',         emoji: '🍔' },
  { id: 'grocery',    label: 'سوبر ماركت',    emoji: '🛒' },
  { id: 'pharmacy',   label: 'صيدليات',       emoji: '💊' },
  { id: 'bakery',     label: 'مخابز وحلويات', emoji: '🥐' },
  { id: 'produce',    label: 'خضار وفاكهة',   emoji: '🥬' },
  { id: 'electronics',label: 'إلكترونيات',    emoji: '📱' },
];

export const STORES: Store[] = [

  // ── مطاعم ──────────────────────────────────────────────────

  {
    id: 'reef-grill',
    name: 'مطعم الريف للمشويات',
    category: 'مشويات وكباب',
    categoryId: 'restaurant',
    emoji: '🥩',
    area: 'دمياط الجديدة',
    address: 'شارع الجيش الرئيسي، أمام بنك مصر',
    phone: '010-9876-5432',
    rating: 4.8,
    reviews: 1420,
    deliveryTime: '35–50 دقيقة',
    deliveryFee: 20,
    minOrder: 80,
    tagline: 'أشهى مشويات دمياط — لحوم طازجة يومياً',
    menu: [
      { section: 'مشويات', items: [
        { id: 'rg1', name: 'كباب حلة (10 أصابع)', desc: 'لحم ضأن مفروم مشوي على الفحم', price: 220, emoji: '🥩' },
        { id: 'rg2', name: 'كفتة مشوية (8 قطع)', desc: 'كفتة بلدية مع بصل وطماطم', price: 180, emoji: '🥩' },
        { id: 'rg3', name: 'ربع فراخ مشوي', desc: 'فراخ بلدي مشوي مع توابل خاصة', price: 95, emoji: '🍗' },
        { id: 'rg4', name: 'نص فراخ مشوي', desc: 'نص فراخ كامل مع سلطة', price: 175, emoji: '🍗' },
        { id: 'rg5', name: 'سيخ كباب + خبز + سلطة', desc: 'وجبة كاملة', price: 140, emoji: '🥙' },
      ]},
      { section: 'وجبات عائلية', items: [
        { id: 'rg6', name: 'تنة كباب + فراخ (4 أشخاص)', desc: 'مشكل مشاوي مع أرز وسلطة وعيش', price: 580, emoji: '🍽️' },
        { id: 'rg7', name: 'فراخ كاملة مشوية', desc: 'فراخ بلدي كاملة', price: 340, emoji: '🐓' },
      ]},
      { section: 'إضافات', items: [
        { id: 'rg8', name: 'أرز بخاري', price: 35, emoji: '🍚' },
        { id: 'rg9', name: 'سلطة خضراء', price: 20, emoji: '🥗' },
        { id: 'rg10', name: 'طحينة', price: 15, emoji: '🫙' },
        { id: 'rg11', name: 'عيش بلدي (6 أرغفة)', price: 12, emoji: '🫓' },
      ]},
      { section: 'مشروبات', items: [
        { id: 'rg12', name: 'عصير ليمون بالنعناع', price: 25, emoji: '🍋' },
        { id: 'rg13', name: 'مياه معدنية 1.5 لتر', price: 12, emoji: '💧' },
        { id: 'rg14', name: 'بيبسي كانز', price: 18, emoji: '🥤' },
      ]},
    ],
  },

  {
    id: 'captain-seafood',
    name: 'كابتن للأسماك والمأكولات البحرية',
    category: 'مأكولات بحرية',
    categoryId: 'restaurant',
    emoji: '🦐',
    area: 'دمياط الجديدة',
    address: 'كورنيش دمياط الجديدة، بجوار الكورنيش',
    phone: '012-3456-7890',
    rating: 4.9,
    reviews: 2340,
    deliveryTime: '40–60 دقيقة',
    deliveryFee: 25,
    minOrder: 120,
    tagline: 'جمبري دمياط الشهير — طازج من البحر مباشرة',
    menu: [
      { section: 'أطباق رئيسية', items: [
        { id: 'cs1', name: 'جمبري مشوي (½ كيلو)', desc: 'جمبري بحري طازج مشوي بالزبدة والثوم', price: 280, emoji: '🦐' },
        { id: 'cs2', name: 'سمك بلطي طازج (كيلو)', desc: 'مقلي أو مشوي — مع طحينة وأرز صيادية', price: 160, emoji: '🐟' },
        { id: 'cs3', name: 'سمك دنيس مشوي', desc: 'دنيس طازج بالليمون والأعشاب', price: 220, emoji: '🐠' },
        { id: 'cs4', name: 'كاليماري مقلي', desc: 'حلقات كاليماري مقرمشة مع صوص الثوم', price: 195, emoji: '🦑' },
        { id: 'cs5', name: 'صينية جمبري بالكريمة', desc: 'جمبري بالكريمة والجبنة في الفرن', price: 320, emoji: '🦐' },
      ]},
      { section: 'وجبات مشكل', items: [
        { id: 'cs6', name: 'مشكل بحري للاتنين', desc: 'جمبري + سمك + كاليماري + أرز + سلطة', price: 480, emoji: '🍽️' },
        { id: 'cs7', name: 'فيشاند شيبس', desc: 'سمك مقلي مقرمش مع بطاطس وصوص', price: 130, emoji: '🍟' },
      ]},
      { section: 'مقبلات وإضافات', items: [
        { id: 'cs8', name: 'أرز صيادية', price: 40, emoji: '🍚' },
        { id: 'cs9', name: 'صلصة طحينة', price: 20, emoji: '🫙' },
        { id: 'cs10', name: 'سلطة بلدية', price: 25, emoji: '🥗' },
      ]},
    ],
  },

  {
    id: 'mama-kitchen',
    name: 'مطبخ ماما — أكل بيتي',
    category: 'أكل بيتي ومطبخ',
    categoryId: 'restaurant',
    emoji: '🍲',
    area: 'دمياط الجديدة',
    address: 'المجاورة الثالثة، شارع المدارس',
    phone: '011-2233-4455',
    rating: 4.7,
    reviews: 876,
    deliveryTime: '45–65 دقيقة',
    deliveryFee: 15,
    minOrder: 70,
    tagline: 'طعم البيت يوصلك حيث أنت',
    menu: [
      { section: 'أطباق يومية', items: [
        { id: 'mk1', name: 'فراخ محمرة بالفرن', desc: 'فراخ بلدي بالبطاطس والتوابل', price: 140, emoji: '🍗' },
        { id: 'mk2', name: 'كفتة في الصلصة', desc: 'كفتة باللحم مع صلصة الطماطم والخضار', price: 120, emoji: '🥘' },
        { id: 'mk3', name: 'صينية مكرونة بشاميل', desc: 'باستا بشاميل كريمية بالفرن', price: 95, emoji: '🍝' },
        { id: 'mk4', name: 'أرنب بالكريمة', desc: 'أرنب طازج بالكريمة والمشروم', price: 180, emoji: '🥘' },
        { id: 'mk5', name: 'فتة لحمة', desc: 'لحمة مع عيش وأرز وصلصة', price: 155, emoji: '🍲' },
      ]},
      { section: 'شوربة وسلطات', items: [
        { id: 'mk6', name: 'شوربة خضار', price: 35, emoji: '🍜' },
        { id: 'mk7', name: 'سلطة خضراء', price: 25, emoji: '🥗' },
        { id: 'mk8', name: 'متبل', price: 30, emoji: '🫙' },
      ]},
      { section: 'مشروبات وحلويات', items: [
        { id: 'mk9', name: 'عصائر طبيعية', price: 30, emoji: '🍹' },
        { id: 'mk10', name: 'أم علي (طبق)', price: 45, emoji: '🍮' },
      ]},
    ],
  },

  // ── سوبر ماركت ──────────────────────────────────────────────

  {
    id: 'cleopatra-market',
    name: 'سوبر ماركت كليوباترا',
    category: 'سوبر ماركت',
    categoryId: 'grocery',
    emoji: '🛒',
    area: 'دمياط الجديدة',
    address: 'شارع الجيش — المجاورة الأولى',
    phone: '057-226-1234',
    rating: 4.6,
    reviews: 1120,
    deliveryTime: '40–60 دقيقة',
    deliveryFee: 20,
    minOrder: 100,
    tagline: 'كل احتياجات بيتك بسعر الجملة',
    menu: [
      { section: 'ألبان وأجبان', items: [
        { id: 'cm1', name: 'لبن جهينة كامل الدسم 1 لتر', price: 42, emoji: '🥛' },
        { id: 'cm2', name: 'جبنة بيضاء مصرية ½ كيلو', price: 72, emoji: '🧀' },
        { id: 'cm3', name: 'جبنة روم (100 جم)', price: 38, emoji: '🧀' },
        { id: 'cm4', name: 'زبادي جهينة (6 حبات)', price: 48, emoji: '🥛' },
        { id: 'cm5', name: 'قشطة كيلو', price: 160, emoji: '🍶' },
      ]},
      { section: 'بقالة أساسية', items: [
        { id: 'cm6', name: 'أرز مصري بلدي 5 كيلو', price: 145, emoji: '🍚' },
        { id: 'cm7', name: 'زيت عباد شمس 2.25 لتر', price: 162, emoji: '🛢️' },
        { id: 'cm8', name: 'سكر أبيض كيلو', price: 36, emoji: '🍬' },
        { id: 'cm9', name: 'مكرونة بيلا 500 جم', price: 22, emoji: '🍝' },
        { id: 'cm10', name: 'طماطم معلبة (2 علبة)', price: 28, emoji: '🥫' },
        { id: 'cm11', name: 'عدس أحمر كيلو', price: 45, emoji: '🫘' },
      ]},
      { section: 'مواد تنظيف', items: [
        { id: 'cm12', name: 'أريال أوتوماتيك 3 كيلو', price: 185, emoji: '🧼' },
        { id: 'cm13', name: 'صابون أطباق برتقال', price: 52, emoji: '🧴' },
        { id: 'cm14', name: 'فيري سائل (750 مل)', price: 38, emoji: '🧴' },
        { id: 'cm15', name: 'مناديل 10 علبة', price: 95, emoji: '🧻' },
      ]},
      { section: 'مشروبات ومعلبات', items: [
        { id: 'cm16', name: 'بيبسي 1.5 لتر', price: 22, emoji: '🥤' },
        { id: 'cm17', name: 'ريدبول علبة 250 مل', price: 38, emoji: '🥤' },
        { id: 'cm18', name: 'مياه سيوة 1.5 لتر', price: 14, emoji: '💧' },
      ]},
    ],
  },

  // ── صيدليات ─────────────────────────────────────────────────

  {
    id: 'ezaby-pharmacy',
    name: 'صيدلية العزبي',
    category: 'صيدلية',
    categoryId: 'pharmacy',
    emoji: '💊',
    area: 'دمياط الجديدة',
    address: 'شارع الجيش، بجوار البنك الأهلي',
    phone: '057-225-5500',
    rating: 4.9,
    reviews: 2180,
    deliveryTime: '20–35 دقيقة',
    deliveryFee: 10,
    minOrder: 0,
    tagline: 'أدويتك ومستلزماتك الطبية بضمان وسرعة',
    menu: [
      { section: 'مسكنات وأدوية بدون روشتة', items: [
        { id: 'ez1', name: 'بنادول إكسترا 24 قرص', price: 42, emoji: '💊' },
        { id: 'ez2', name: 'كاتافلام 25 مجم', price: 55, emoji: '💊' },
        { id: 'ez3', name: 'باراسيتامول 500 (20 قرص)', price: 18, emoji: '💊' },
        { id: 'ez4', name: 'فيتامين سي 1000 فوار (20 قرص)', price: 68, emoji: '🍊' },
        { id: 'ez5', name: 'أوميجا 3 (30 كبسولة)', price: 145, emoji: '💊' },
      ]},
      { section: 'العناية الشخصية', items: [
        { id: 'ez6', name: 'جل معقم يدين 500 مل', price: 38, emoji: '🧴' },
        { id: 'ez7', name: 'واقي شمس SPF50 (50 مل)', price: 180, emoji: '🧴' },
        { id: 'ez8', name: 'كريم نيفيا للوجه (50 مل)', price: 125, emoji: '🧴' },
        { id: 'ez9', name: 'كمامات طبية 50 قطعة', price: 75, emoji: '😷' },
      ]},
      { section: 'مستلزمات طبية', items: [
        { id: 'ez10', name: 'كمادات وشاش طبي', price: 45, emoji: '🩹' },
        { id: 'ez11', name: 'ضغط دم رقمي يد', price: 820, emoji: '🩺' },
        { id: 'ez12', name: 'ترمومتر رقمي', price: 195, emoji: '🌡️' },
      ]},
      { section: 'مستلزمات الأطفال', items: [
        { id: 'ez13', name: 'حفاضات باميرز مقاس 3 (40 حبة)', price: 260, emoji: '🍼' },
        { id: 'ez14', name: 'مناديل بيبي ماكس (80 ورقة)', price: 45, emoji: '🧻' },
        { id: 'ez15', name: 'لبن نان 1 علبة (400 جم)', price: 345, emoji: '🍼' },
      ]},
    ],
  },

  // ── مخابز وحلويات ────────────────────────────────────────────

  {
    id: 'damietta-sweets',
    name: 'حلويات دمياط الأصيلة',
    category: 'حلويات شرقية وغربية',
    categoryId: 'bakery',
    emoji: '🍰',
    area: 'دمياط الجديدة',
    address: 'شارع الكباش — أمام ميدان المدينة',
    phone: '057-226-8899',
    rating: 4.9,
    reviews: 3200,
    deliveryTime: '35–55 دقيقة',
    deliveryFee: 18,
    minOrder: 60,
    tagline: 'دمياط مدينة الحلوى — القشطة الأصلية والكنافة الحقيقية',
    menu: [
      { section: 'حلويات شرقية', items: [
        { id: 'ds1', name: 'كنافة بالقشطة (كيلو)', desc: 'كنافة بالقشطة الدمياطية الأصلية', price: 220, emoji: '🍮' },
        { id: 'ds2', name: 'بقلاوة مشكلة (كيلو)', desc: 'فستق وكاجو وجوز', price: 320, emoji: '🥮' },
        { id: 'ds3', name: 'بسبوسة بالقشطة (كيلو)', price: 150, emoji: '🍰' },
        { id: 'ds4', name: 'حلاوة طحينة دمياطي (كيلو)', price: 180, emoji: '🫙' },
        { id: 'ds5', name: 'رز بلبن (طبق)', price: 45, emoji: '🍮' },
        { id: 'ds6', name: 'أم علي (طبق)', price: 55, emoji: '🍮' },
      ]},
      { section: 'كيك وتورتة', items: [
        { id: 'ds7', name: 'تورتة شوكولاتة (6 أشخاص)', price: 380, emoji: '🎂' },
        { id: 'ds8', name: 'كيك عيد ميلاد مخصص', desc: 'اتصل لمعرفة التفاصيل', price: 450, emoji: '🎂' },
        { id: 'ds9', name: 'كب كيك (6 حبات)', price: 120, emoji: '🧁' },
        { id: 'ds10', name: 'شيز كيك نيويورك (6 أشخاص)', price: 350, emoji: '🍰' },
      ]},
      { section: 'مخبوزات طازجة', items: [
        { id: 'ds11', name: 'كرواسون زبدة (6 حبات)', price: 96, emoji: '🥐' },
        { id: 'ds12', name: 'فطير مشلتت بالعسل', price: 85, emoji: '🥞' },
        { id: 'ds13', name: 'دونات مشكل (6 حبات)', price: 90, emoji: '🍩' },
      ]},
    ],
  },

  // ── خضار وفاكهة ─────────────────────────────────────────────

  {
    id: 'nile-produce',
    name: 'خضار وفاكهة النيل',
    category: 'خضار وفاكهة طازجة',
    categoryId: 'produce',
    emoji: '🥬',
    area: 'دمياط الجديدة',
    address: 'سوق دمياط الجديدة، المجاورة الخامسة',
    phone: '010-1122-3344',
    rating: 4.5,
    reviews: 680,
    deliveryTime: '40–55 دقيقة',
    deliveryFee: 15,
    minOrder: 60,
    tagline: 'مباشرة من مزارع كفر سعد — طازج كل صباح',
    menu: [
      { section: 'خضروات', items: [
        { id: 'np1', name: 'طماطم (كيلو)', price: 22, emoji: '🍅' },
        { id: 'np2', name: 'بطاطس (كيلو)', price: 20, emoji: '🥔' },
        { id: 'np3', name: 'بصل أبيض (كيلو)', price: 18, emoji: '🧅' },
        { id: 'np4', name: 'خيار (كيلو)', price: 15, emoji: '🥒' },
        { id: 'np5', name: 'جزر (كيلو)', price: 16, emoji: '🥕' },
        { id: 'np6', name: 'فلفل رومي (كيلو)', price: 35, emoji: '🫑' },
        { id: 'np7', name: 'ملوخية (كيلو)', price: 28, emoji: '🥬' },
        { id: 'np8', name: 'كوسة (كيلو)', price: 20, emoji: '🥬' },
        { id: 'np9', name: 'باذنجان (كيلو)', price: 18, emoji: '🍆' },
      ]},
      { section: 'فاكهة', items: [
        { id: 'np10', name: 'موز إكوادور (كيلو)', price: 35, emoji: '🍌' },
        { id: 'np11', name: 'تفاح أحمر (كيلو)', price: 65, emoji: '🍎' },
        { id: 'np12', name: 'برتقال بلدي (كيلو)', price: 28, emoji: '🍊' },
        { id: 'np13', name: 'عنب أحمر (كيلو)', price: 55, emoji: '🍇' },
        { id: 'np14', name: 'مانجو فاكهة (كيلو)', price: 70, emoji: '🥭' },
        { id: 'np15', name: 'جوافة (كيلو)', price: 30, emoji: '🍐' },
        { id: 'np16', name: 'كمثرى (كيلو)', price: 58, emoji: '🍐' },
      ]},
      { section: 'بقوليات', items: [
        { id: 'np17', name: 'فول (كيلو)', price: 22, emoji: '🫘' },
        { id: 'np18', name: 'فاصوليا خضراء (كيلو)', price: 32, emoji: '🫘' },
      ]},
    ],
  },

  // ── إلكترونيات ───────────────────────────────────────────────

  {
    id: 'mobile-zone',
    name: 'موبايل زون دمياط',
    category: 'موبايلات وإلكترونيات',
    categoryId: 'electronics',
    emoji: '📱',
    area: 'دمياط الجديدة',
    address: 'شارع محور الكباش — بجوار فودافون',
    phone: '057-227-3456',
    rating: 4.6,
    reviews: 490,
    deliveryTime: '45–70 دقيقة',
    deliveryFee: 30,
    minOrder: 100,
    tagline: 'أحدث إكسسوارات الموبايل والإلكترونيات',
    menu: [
      { section: 'شواحن وكابلات', items: [
        { id: 'mz1', name: 'شاحن سامسونج أصلي 25 واط', price: 320, emoji: '🔌' },
        { id: 'mz2', name: 'شاحن أبل أصلي 20 واط', price: 380, emoji: '🔌' },
        { id: 'mz3', name: 'كابل تايب-سي 2 متر', price: 95, emoji: '🔌' },
        { id: 'mz4', name: 'كابل آيفون (Lightning)', price: 120, emoji: '🔌' },
        { id: 'mz5', name: 'محول OTG تايب-سي', price: 85, emoji: '🔌' },
      ]},
      { section: 'سماعات', items: [
        { id: 'mz6', name: 'سماعة JBL بلوتوث', price: 680, emoji: '🎧' },
        { id: 'mz7', name: 'إيربودز TWS رخيص', price: 220, emoji: '🎧' },
        { id: 'mz8', name: 'سماعة سلكية للموبايل', price: 85, emoji: '🎧' },
      ]},
      { section: 'حماية وإكسسوار', items: [
        { id: 'mz9', name: 'كفر حماية لسامسونج', price: 85, emoji: '📱' },
        { id: 'mz10', name: 'كفر حماية لآيفون', price: 120, emoji: '📱' },
        { id: 'mz11', name: 'لاصق حماية شاشة', price: 55, emoji: '📱' },
      ]},
      { section: 'باور بانك وشحن', items: [
        { id: 'mz12', name: 'باور بانك 20000 مللي', price: 780, emoji: '🔋' },
        { id: 'mz13', name: 'باور بانك 10000 مللي', price: 480, emoji: '🔋' },
        { id: 'mz14', name: 'ساعة ذكية ميزبان', price: 1450, emoji: '⌚' },
      ]},
    ],
  },
];

export function getStore(id: string): Store | undefined {
  return STORES.find(s => s.id === id);
}
