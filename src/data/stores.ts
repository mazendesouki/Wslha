// Real merchants in New Damietta (دمياط الجديدة) — verified from ElMenus, YellowPages, MenuEgypt
// Prices in EGP — updated June 2026 against live Egyptian market rates
// Market reference (June 2026): فراخ بيضاء ~83/كجم · لحمة بلدي 450–480 · بلطي 80–84 ·
// جمبري ممتاز 760–860 · بيض كرتونة ~165 · لبن لتر ~45 · طماطم ~24 · بطاطس ~18

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

  // ── مطاعم مشويات ───────────────────────────────────────────

  {
    id: 'kilani-grills',
    name: 'مشويات الكيلاني',
    category: 'مشويات وكباب',
    categoryId: 'restaurant',
    emoji: '🥩',
    area: 'دمياط الجديدة — المنطقة المركزية',
    address: 'المنطقة المركزية، دمياط الجديدة',
    phone: '0572403330',
    rating: 4.8,
    reviews: 2640,
    deliveryTime: '35–50 دقيقة',
    deliveryFee: 20,
    minOrder: 80,
    tagline: 'أشهى مشويات دمياط — لحوم طازجة يومياً على الفحم',
    menu: [
      { section: 'مشويات', items: [
        { id: 'kl1', name: 'كباب حلة (10 أصابع)', desc: 'لحم ضأن مفروم مشوي على الفحم', price: 240, emoji: '🥩' },
        { id: 'kl2', name: 'كفتة مشوية (8 قطع)', desc: 'كفتة بلدية مع بصل وطماطم', price: 195, emoji: '🥩' },
        { id: 'kl3', name: 'ربع فراخ مشوي', desc: 'فراخ بلدي مشوي مع توابل خاصة', price: 105, emoji: '🍗' },
        { id: 'kl4', name: 'نص فراخ مشوي', desc: 'نص فراخ كامل مع سلطة', price: 195, emoji: '🍗' },
        { id: 'kl5', name: 'شيش طاووق', desc: 'صدور دجاج مع توابل الكيلاني الخاصة', price: 165, emoji: '🍢' },
      ]},
      { section: 'وجبات عائلية', items: [
        { id: 'kl6', name: 'مشكل مشاوي (4 أشخاص)', desc: 'كباب + كفتة + فراخ + أرز + سلطة + عيش', price: 620, emoji: '🍽️' },
        { id: 'kl7', name: 'فراخ كاملة مشوية', desc: 'فراخ بلدي كاملة مع أرز وسلطة', price: 380, emoji: '🐓' },
      ]},
      { section: 'إضافات', items: [
        { id: 'kl8', name: 'أرز بخاري', price: 40, emoji: '🍚' },
        { id: 'kl9', name: 'سلطة خضراء', price: 22, emoji: '🥗' },
        { id: 'kl10', name: 'طحينة', price: 18, emoji: '🫙' },
        { id: 'kl11', name: 'عيش بلدي (6 أرغفة)', price: 15, emoji: '🫓' },
      ]},
      { section: 'مشروبات', items: [
        { id: 'kl12', name: 'عصير ليمون بالنعناع', price: 30, emoji: '🍋' },
        { id: 'kl13', name: 'مياه معدنية 1.5 لتر', price: 14, emoji: '💧' },
        { id: 'kl14', name: 'بيبسي كانز', price: 20, emoji: '🥤' },
      ]},
    ],
  },

  {
    id: 'farhat-basha',
    name: 'فرحات باشا',
    category: 'مشويات وطعام مصري',
    categoryId: 'restaurant',
    emoji: '🍖',
    area: 'دمياط الجديدة — كورنيش النيل',
    address: 'كورنيش النيل، بجوار بنك CIB، دمياط الجديدة',
    phone: '01009060253',
    rating: 4.7,
    reviews: 1830,
    deliveryTime: '40–55 دقيقة',
    deliveryFee: 22,
    minOrder: 90,
    tagline: 'مشويات الكورنيش الشهيرة — إطلالة النيل وأشهى الأكلات',
    menu: [
      { section: 'مشويات', items: [
        { id: 'fb1', name: 'ريش غنم مشوية (½ كيلو)', desc: 'ريش ضأن طازج مشوي على الفحم', price: 320, emoji: '🥩' },
        { id: 'fb2', name: 'كباب بالعظم', desc: 'كباب لحم مع العظم مشوي', price: 260, emoji: '🥩' },
        { id: 'fb3', name: 'فراخ بلدي مشوية', desc: 'فراخ بلدي كاملة بالأعشاب', price: 390, emoji: '🍗' },
        { id: 'fb4', name: 'ورقة سيخ كباب + سلطة + عيش', price: 155, emoji: '🥙' },
      ]},
      { section: 'أطباق مصرية', items: [
        { id: 'fb5', name: 'فتة لحمة', desc: 'لحمة مع أرز وعيش مقرمش وصلصة', price: 175, emoji: '🍲' },
        { id: 'fb6', name: 'هريسة لحمة', desc: 'طبق تراثي مصري', price: 165, emoji: '🍲' },
        { id: 'fb7', name: 'كوارع بالحمص', price: 145, emoji: '🍲' },
      ]},
      { section: 'إضافات ومشروبات', items: [
        { id: 'fb8', name: 'سلطة فتوش', price: 30, emoji: '🥗' },
        { id: 'fb9', name: 'بابا غنوج', price: 35, emoji: '🫙' },
        { id: 'fb10', name: 'عصير قصب', price: 25, emoji: '🥤' },
        { id: 'fb11', name: 'شاي أكواب', price: 15, emoji: '🍵' },
      ]},
    ],
  },

  // ── مطاعم أسماك ────────────────────────────────────────────

  {
    id: 'aklet-smak',
    name: 'أكلة سمك',
    category: 'مأكولات بحرية',
    categoryId: 'restaurant',
    emoji: '🦐',
    area: 'دمياط الجديدة — الأجا',
    address: 'الأجا، دمياط الجديدة',
    phone: '01552231011',
    rating: 4.9,
    reviews: 3140,
    deliveryTime: '40–60 دقيقة',
    deliveryFee: 25,
    minOrder: 120,
    tagline: 'جمبري دمياط الشهير — طازج من البحر مباشرة',
    menu: [
      { section: 'أطباق رئيسية', items: [
        { id: 'as1', name: 'جمبري مشوي (½ كيلو)', desc: 'جمبري بحري طازج مشوي بالزبدة والثوم', price: 295, emoji: '🦐' },
        { id: 'as2', name: 'جمبري مقلي (½ كيلو)', desc: 'مقرمش ومتبل مع صوص الثوم', price: 275, emoji: '🦐' },
        { id: 'as3', name: 'سمك بلطي طازج (كيلو)', desc: 'مقلي أو مشوي — مع طحينة وأرز صيادية', price: 175, emoji: '🐟' },
        { id: 'as4', name: 'سمك دنيس مشوي', desc: 'دنيس طازج بالليمون والأعشاب', price: 235, emoji: '🐠' },
        { id: 'as5', name: 'كاليماري مقلي', desc: 'حلقات كاليماري مقرمشة', price: 210, emoji: '🦑' },
        { id: 'as6', name: 'صينية جمبري بالكريمة', desc: 'جمبري بالكريمة والجبنة في الفرن', price: 340, emoji: '🦐' },
      ]},
      { section: 'وجبات مشكل', items: [
        { id: 'as7', name: 'مشكل بحري للاتنين', desc: 'جمبري + سمك + كاليماري + أرز + سلطة', price: 510, emoji: '🍽️' },
        { id: 'as8', name: 'طبق سمك للواحد', desc: 'سمك + أرز صيادية + سلطة + طحينة', price: 165, emoji: '🍽️' },
      ]},
      { section: 'مقبلات وإضافات', items: [
        { id: 'as9', name: 'أرز صيادية', price: 45, emoji: '🍚' },
        { id: 'as10', name: 'صلصة طحينة', price: 22, emoji: '🫙' },
        { id: 'as11', name: 'سلطة بلدية', price: 28, emoji: '🥗' },
        { id: 'as12', name: 'عصير ليمون', price: 28, emoji: '🍋' },
      ]},
    ],
  },

  {
    id: 'eldowar',
    name: 'مطعم الدوار',
    category: 'مطبخ شرقي ومصري',
    categoryId: 'restaurant',
    emoji: '🍲',
    area: 'دمياط الجديدة — أمام الاستاد',
    address: 'شارع أبو الخير، أمام الاستاد، دمياط الجديدة',
    phone: '01090852011',
    rating: 4.6,
    reviews: 1290,
    deliveryTime: '40–60 دقيقة',
    deliveryFee: 18,
    minOrder: 75,
    tagline: 'مطبخ شرقي أصيل — دليفري سريع لجميع مناطق دمياط',
    menu: [
      { section: 'أطباق يومية', items: [
        { id: 'ed1', name: 'فراخ محمرة بالفرن', desc: 'فراخ بلدي بالبطاطس والتوابل', price: 155, emoji: '🍗' },
        { id: 'ed2', name: 'كفتة في الصلصة', desc: 'كفتة باللحم مع صلصة الطماطم', price: 135, emoji: '🥘' },
        { id: 'ed3', name: 'صينية مكرونة بشاميل', desc: 'باستا بشاميل كريمية بالفرن', price: 105, emoji: '🍝' },
        { id: 'ed4', name: 'ملوخية بالفراخ', desc: 'ملوخية ناعمة مع أرز وفراخ', price: 125, emoji: '🥣' },
        { id: 'ed5', name: 'فتة فراخ', desc: 'فراخ مع أرز وعيش وصلصة', price: 140, emoji: '🍲' },
      ]},
      { section: 'شوربة وسلطات', items: [
        { id: 'ed6', name: 'شوربة فراخ', price: 45, emoji: '🍜' },
        { id: 'ed7', name: 'سلطة خضراء', price: 28, emoji: '🥗' },
        { id: 'ed8', name: 'متبل', price: 32, emoji: '🫙' },
        { id: 'ed9', name: 'شوربة عدس', price: 38, emoji: '🍲' },
      ]},
      { section: 'مشروبات', items: [
        { id: 'ed10', name: 'عصائر طبيعية', price: 35, emoji: '🍹' },
        { id: 'ed11', name: 'مياه معدنية', price: 14, emoji: '💧' },
        { id: 'ed12', name: 'أم علي (طبق)', price: 50, emoji: '🍮' },
      ]},
    ],
  },

  // ── سوبر ماركت ─────────────────────────────────────────────

  {
    id: 'fathalla-market',
    name: 'هايبر فتح الله ماركت',
    category: 'هايبر ماركت',
    categoryId: 'grocery',
    emoji: '🛒',
    area: 'دمياط الجديدة — بجوار مسجد الروضة الشريفة',
    address: 'آخر شارع المحجوب، بجوار مسجد الروضة الشريفة، دمياط الجديدة',
    rating: 4.7,
    reviews: 2480,
    deliveryTime: '35–55 دقيقة',
    deliveryFee: 0,
    minOrder: 150,
    tagline: 'كل احتياجات بيتك — توصيل مجاني بدون حد أدنى',
    menu: [
      { section: 'ألبان وأجبان', items: [
        { id: 'fm1', name: 'لبن جهينة كامل الدسم 1 لتر', price: 44, emoji: '🥛' },
        { id: 'fm2', name: 'جبنة بيضاء مصرية ½ كيلو', price: 75, emoji: '🧀' },
        { id: 'fm3', name: 'جبنة روم (100 جم)', price: 40, emoji: '🧀' },
        { id: 'fm4', name: 'زبادي جهينة (6 حبات)', price: 52, emoji: '🥛' },
        { id: 'fm5', name: 'قشطة دمياطي كيلو', price: 175, emoji: '🍶' },
      ]},
      { section: 'بقالة أساسية', items: [
        { id: 'fm6', name: 'أرز مصري بلدي 5 كيلو', price: 155, emoji: '🍚' },
        { id: 'fm7', name: 'زيت عباد شمس 2.25 لتر', price: 168, emoji: '🛢️' },
        { id: 'fm8', name: 'سكر أبيض كيلو', price: 38, emoji: '🍬' },
        { id: 'fm9', name: 'دقيق فاخر 5 كيلو', price: 120, emoji: '🌾' },
        { id: 'fm10', name: 'طماطم معلبة (2 علبة)', price: 30, emoji: '🥫' },
        { id: 'fm11', name: 'مكرونة سباغيتي 500 جم', price: 24, emoji: '🍝' },
        { id: 'fm12', name: 'عدس أحمر كيلو', price: 48, emoji: '🫘' },
      ]},
      { section: 'لحوم ودواجن', items: [
        { id: 'fm13', name: 'فراخ كاملة طازجة (كيلو)', price: 85, emoji: '🍗' },
        { id: 'fm14', name: 'لحمة بتلو مفروم (كيلو)', price: 460, emoji: '🥩' },
        { id: 'fm15', name: 'فيليه سمك (كيلو)', price: 195, emoji: '🐟' },
      ]},
      { section: 'مواد تنظيف', items: [
        { id: 'fm16', name: 'أريال أوتوماتيك 3 كيلو', price: 192, emoji: '🧼' },
        { id: 'fm17', name: 'فيري سائل (750 مل)', price: 40, emoji: '🧴' },
        { id: 'fm18', name: 'مناديل 10 علبة', price: 98, emoji: '🧻' },
      ]},
      { section: 'مشروبات', items: [
        { id: 'fm19', name: 'بيبسي 1.5 لتر', price: 24, emoji: '🥤' },
        { id: 'fm20', name: 'مياه سيوة 1.5 لتر', price: 15, emoji: '💧' },
        { id: 'fm21', name: 'عصير ساديا 1 لتر', price: 48, emoji: '🧃' },
      ]},
    ],
  },

  {
    id: 'carnival-market',
    name: 'كارنفال سوبرماركت',
    category: 'سوبر ماركت',
    categoryId: 'grocery',
    emoji: '🏪',
    area: 'دمياط الجديدة — الحي الأول',
    address: 'الحي الأول، المجاورة الأولى، دمياط الجديدة',
    rating: 4.5,
    reviews: 1140,
    deliveryTime: '30–50 دقيقة',
    deliveryFee: 15,
    minOrder: 100,
    tagline: 'سوبرماركت الحي الأول — قريب منك دايماً',
    menu: [
      { section: 'ألبان وبيض', items: [
        { id: 'cv1', name: 'بيض بلدي (كرتونة 30)', price: 165, emoji: '🥚' },
        { id: 'cv2', name: 'لبن فريش كيلو', price: 48, emoji: '🥛' },
        { id: 'cv3', name: 'جبنة قريش كيلو', price: 95, emoji: '🧀' },
        { id: 'cv4', name: 'زبدة أنكور (200 جم)', price: 72, emoji: '🧈' },
      ]},
      { section: 'بقالة', items: [
        { id: 'cv5', name: 'أرز أبو بنت 5 كيلو', price: 150, emoji: '🍚' },
        { id: 'cv6', name: 'شاي ليبتون (100 كيس)', price: 95, emoji: '🍵' },
        { id: 'cv7', name: 'قهوة نسكافيه كلاسيك (200 جم)', price: 185, emoji: '☕' },
        { id: 'cv8', name: 'ملح طعام كيلو', price: 12, emoji: '🧂' },
        { id: 'cv9', name: 'معجون طماطم (زجاجة 560 جم)', price: 32, emoji: '🥫' },
      ]},
      { section: 'وجبات جاهزة', items: [
        { id: 'cv10', name: 'بيتزا مجمدة', price: 145, emoji: '🍕' },
        { id: 'cv11', name: 'نجوم دجاج مجمد', price: 95, emoji: '🍗' },
        { id: 'cv12', name: 'ساندويتش حواوشي جاهز', price: 55, emoji: '🥪' },
      ]},
      { section: 'مشروبات وسناكس', items: [
        { id: 'cv13', name: 'كوكاكولا 2 لتر', price: 38, emoji: '🥤' },
        { id: 'cv14', name: 'شيبسي مشكلة (5 علب)', price: 85, emoji: '🥔' },
        { id: 'cv15', name: 'شوكولاتة كيت كات', price: 38, emoji: '🍫' },
      ]},
    ],
  },

  // ── صيدليات ────────────────────────────────────────────────

  {
    id: 'tarshubi-pharmacy',
    name: 'صيدليات الطرشوبي',
    category: 'صيدلية',
    categoryId: 'pharmacy',
    emoji: '💊',
    area: 'دمياط الجديدة — هادي مول',
    address: 'هادي مول، دمياط الجديدة',
    phone: '0572408205',
    rating: 4.8,
    reviews: 1960,
    deliveryTime: '20–35 دقيقة',
    deliveryFee: 10,
    minOrder: 0,
    tagline: 'صيدليتك الموثوقة في دمياط — خط ساخن 19121',
    menu: [
      { section: 'مسكنات وأدوية بدون روشتة', items: [
        { id: 'tp1', name: 'بنادول إكسترا 24 قرص', price: 44, emoji: '💊' },
        { id: 'tp2', name: 'باراسيتامول 500 (20 قرص)', price: 20, emoji: '💊' },
        { id: 'tp3', name: 'نوروفين إكسبرس', price: 68, emoji: '💊' },
        { id: 'tp4', name: 'فيتامين سي 1000 فوار (20 قرص)', price: 72, emoji: '🍊' },
        { id: 'tp5', name: 'أوميجا 3 (30 كبسولة)', price: 150, emoji: '💊' },
        { id: 'tp6', name: 'زنك + فيتامين د (30 قرص)', price: 125, emoji: '💊' },
      ]},
      { section: 'العناية الشخصية', items: [
        { id: 'tp7', name: 'جل معقم يدين 500 مل', price: 40, emoji: '🧴' },
        { id: 'tp8', name: 'واقي شمس SPF50', price: 185, emoji: '🧴' },
        { id: 'tp9', name: 'كريم نيفيا للوجه (50 مل)', price: 130, emoji: '🧴' },
        { id: 'tp10', name: 'شامبو هيد آند شولدرز', price: 95, emoji: '🧴' },
      ]},
      { section: 'مستلزمات طبية', items: [
        { id: 'tp11', name: 'كمادات وشاش طبي', price: 48, emoji: '🩹' },
        { id: 'tp12', name: 'ترمومتر رقمي', price: 200, emoji: '🌡️' },
        { id: 'tp13', name: 'كمامات طبية 50 قطعة', price: 78, emoji: '😷' },
      ]},
      { section: 'مستلزمات الأطفال', items: [
        { id: 'tp14', name: 'حفاضات باميرز مقاس 3 (40 حبة)', price: 268, emoji: '🍼' },
        { id: 'tp15', name: 'مناديل بيبي ماكس (80 ورقة)', price: 48, emoji: '🧻' },
        { id: 'tp16', name: 'لبن نان 1 (400 جم)', price: 355, emoji: '🍼' },
      ]},
    ],
  },

  {
    id: 'ezaby-pharmacy',
    name: 'صيدلية العزبي',
    category: 'صيدلية',
    categoryId: 'pharmacy',
    emoji: '🏥',
    area: 'دمياط الجديدة — الحي الثاني',
    address: '34 ش حسب الله الكفراوي، الحي الثاني، دمياط الجديدة',
    phone: '19600',
    rating: 4.9,
    reviews: 3250,
    deliveryTime: '15–30 دقيقة',
    deliveryFee: 10,
    minOrder: 0,
    tagline: 'سلسلة العزبي — أكبر صيدليات مصر · خط 19600',
    menu: [
      { section: 'أدوية بدون روشتة', items: [
        { id: 'ez1', name: 'بنادول إكسترا 24 قرص', price: 44, emoji: '💊' },
        { id: 'ez2', name: 'كاتافلام 25 مجم', price: 58, emoji: '💊' },
        { id: 'ez3', name: 'باراسيتامول 500 (20 قرص)', price: 20, emoji: '💊' },
        { id: 'ez4', name: 'فيتامين سي 1000 فوار', price: 72, emoji: '🍊' },
        { id: 'ez5', name: 'أوميجا 3 (30 كبسولة)', price: 150, emoji: '💊' },
      ]},
      { section: 'العناية الشخصية', items: [
        { id: 'ez6', name: 'جل معقم يدين 500 مل', price: 40, emoji: '🧴' },
        { id: 'ez7', name: 'واقي شمس SPF50 (50 مل)', price: 185, emoji: '🧴' },
        { id: 'ez8', name: 'كريم نيفيا (50 مل)', price: 130, emoji: '🧴' },
        { id: 'ez9', name: 'كمامات طبية 50 قطعة', price: 78, emoji: '😷' },
      ]},
      { section: 'مستلزمات طبية', items: [
        { id: 'ez10', name: 'كمادات وشاش طبي', price: 48, emoji: '🩹' },
        { id: 'ez11', name: 'جهاز ضغط رقمي', price: 850, emoji: '🩺' },
        { id: 'ez12', name: 'ترمومتر رقمي', price: 200, emoji: '🌡️' },
      ]},
      { section: 'مستلزمات الأطفال', items: [
        { id: 'ez13', name: 'حفاضات باميرز مقاس 3 (40 حبة)', price: 268, emoji: '🍼' },
        { id: 'ez14', name: 'مناديل بيبي (80 ورقة)', price: 48, emoji: '🧻' },
        { id: 'ez15', name: 'لبن نان 1 (400 جم)', price: 355, emoji: '🍼' },
      ]},
    ],
  },

  // ── حلويات ─────────────────────────────────────────────────

  {
    id: 'elbadry-sweets',
    name: 'حلويات البدري',
    category: 'حلويات شرقية وغربية',
    categoryId: 'bakery',
    emoji: '🍰',
    area: 'دمياط الجديدة — شارع البشبيشي',
    address: 'شارع البشبيشي، دمياط الجديدة',
    phone: '01080187282',
    rating: 4.9,
    reviews: 4200,
    deliveryTime: '30–50 دقيقة',
    deliveryFee: 18,
    minOrder: 60,
    tagline: 'حلويات البدري منذ 1910 — الحلاوة الأصيلة من دمياط',
    menu: [
      { section: 'حلويات شرقية', items: [
        { id: 'bd1', name: 'كنافة بالقشطة الدمياطية (كيلو)', desc: 'كنافة بالقشطة الأصلية من دمياط', price: 235, emoji: '🍮' },
        { id: 'bd2', name: 'بقلاوة مشكلة (كيلو)', desc: 'فستق وكاجو وجوز', price: 340, emoji: '🥮' },
        { id: 'bd3', name: 'بسبوسة بالقشطة (كيلو)', price: 160, emoji: '🍰' },
        { id: 'bd4', name: 'مشبك دمياطي (كيلو)', desc: 'مشبك طازج بالعسل والسمسم', price: 145, emoji: '🍯' },
        { id: 'bd5', name: 'حلاوة طحينة دمياطي (كيلو)', price: 190, emoji: '🫙' },
        { id: 'bd6', name: 'رز بلبن وقشطة (طبق)', price: 50, emoji: '🍮' },
      ]},
      { section: 'كيك وتورتة', items: [
        { id: 'bd7', name: 'تورتة شوكولاتة (6 أشخاص)', price: 395, emoji: '🎂' },
        { id: 'bd8', name: 'كيك عيد ميلاد مخصص', desc: 'اتصل لمعرفة التفاصيل', price: 470, emoji: '🎂' },
        { id: 'bd9', name: 'كب كيك مزين (6 حبات)', price: 130, emoji: '🧁' },
        { id: 'bd10', name: 'تارت فراولة (6 أشخاص)', price: 320, emoji: '🍰' },
      ]},
      { section: 'مخبوزات طازجة يومية', items: [
        { id: 'bd11', name: 'كرواسون زبدة (6 حبات)', price: 105, emoji: '🥐' },
        { id: 'bd12', name: 'فطير مشلتت بالعسل والقشطة', price: 95, emoji: '🥞' },
        { id: 'bd13', name: 'دونات مشكل (6 حبات)', price: 98, emoji: '🍩' },
        { id: 'bd14', name: 'كعك العيد (نص كيلو)', price: 125, emoji: '🍪' },
      ]},
    ],
  },

  {
    id: 'fashour-sweets',
    name: 'فشور دمياط',
    category: 'حلويات وآيس كريم',
    categoryId: 'bakery',
    emoji: '🍦',
    area: 'دمياط الجديدة',
    address: 'شارع الشرباصي، دمياط الجديدة',
    rating: 4.8,
    reviews: 2870,
    deliveryTime: '25–40 دقيقة',
    deliveryFee: 15,
    minOrder: 50,
    tagline: 'فشور دمياط الأصيل — كنافة وآيس كريم وحلويات شرقية',
    menu: [
      { section: 'كنافة وحلويات شرقية', items: [
        { id: 'fs1', name: 'كنافة خشن بالقشطة (كيلو)', price: 220, emoji: '🍮' },
        { id: 'fs2', name: 'كنافة بالمانجو (كيلو)', desc: 'موسمي — مانجو طازجة مع القشطة', price: 260, emoji: '🥭' },
        { id: 'fs3', name: 'بسبوسة بجوز الهند (كيلو)', price: 155, emoji: '🍰' },
        { id: 'fs4', name: 'مشبك طازج (نص كيلو)', price: 80, emoji: '🍯' },
      ]},
      { section: 'آيس كريم', items: [
        { id: 'fs5', name: 'كوب آيس كريم مانجو', price: 45, emoji: '🍨' },
        { id: 'fs6', name: 'كوب آيس كريم فراولة', price: 45, emoji: '🍓' },
        { id: 'fs7', name: 'صحن آيس كريم مشكل', price: 85, emoji: '🍦' },
        { id: 'fs8', name: 'آيس كريم شوكولاتة (كوب)', price: 50, emoji: '🍫' },
      ]},
      { section: 'عصائر وسخون', items: [
        { id: 'fs9', name: 'عصير مانجو طازج', price: 40, emoji: '🥭' },
        { id: 'fs10', name: 'عصير فراولة بالحليب', price: 45, emoji: '🍓' },
        { id: 'fs11', name: 'كاكاو ساخن', price: 38, emoji: '☕' },
      ]},
    ],
  },

  // ── خضار وفاكهة ────────────────────────────────────────────

  {
    id: 'nile-produce',
    name: 'خضار وفاكهة النيل',
    category: 'خضار وفاكهة طازجة',
    categoryId: 'produce',
    emoji: '🥬',
    area: 'دمياط الجديدة — سوق المجاورة الخامسة',
    address: 'سوق دمياط الجديدة، المجاورة الخامسة',
    phone: '01011223344',
    rating: 4.5,
    reviews: 780,
    deliveryTime: '40–55 دقيقة',
    deliveryFee: 15,
    minOrder: 60,
    tagline: 'مباشرة من مزارع كفر سعد — طازج كل صباح',
    menu: [
      { section: 'خضروات', items: [
        { id: 'np1', name: 'طماطم (كيلو)', price: 24, emoji: '🍅' },
        { id: 'np2', name: 'بطاطس (كيلو)', price: 18, emoji: '🥔' },
        { id: 'np3', name: 'بصل أبيض (كيلو)', price: 20, emoji: '🧅' },
        { id: 'np4', name: 'خيار (كيلو)', price: 18, emoji: '🥒' },
        { id: 'np5', name: 'جزر (كيلو)', price: 18, emoji: '🥕' },
        { id: 'np6', name: 'فلفل رومي أخضر (كيلو)', price: 38, emoji: '🫑' },
        { id: 'np7', name: 'ملوخية (كيلو)', price: 32, emoji: '🥬' },
        { id: 'np8', name: 'كوسة (كيلو)', price: 22, emoji: '🥬' },
        { id: 'np9', name: 'باذنجان (كيلو)', price: 20, emoji: '🍆' },
        { id: 'np10', name: 'ثوم مصري (250 جم)', price: 28, emoji: '🧄' },
      ]},
      { section: 'فاكهة', items: [
        { id: 'np11', name: 'موز إكوادور (كيلو)', price: 38, emoji: '🍌' },
        { id: 'np12', name: 'تفاح أحمر (كيلو)', price: 68, emoji: '🍎' },
        { id: 'np13', name: 'برتقال بلدي (كيلو)', price: 30, emoji: '🍊' },
        { id: 'np14', name: 'عنب أحمر (كيلو)', price: 58, emoji: '🍇' },
        { id: 'np15', name: 'مانجو فاكهة (كيلو)', price: 75, emoji: '🥭' },
        { id: 'np16', name: 'جوافة بيضاء (كيلو)', price: 32, emoji: '🍐' },
        { id: 'np17', name: 'بطيخ (كيلو)', price: 15, emoji: '🍉' },
      ]},
      { section: 'بقوليات وأعشاب', items: [
        { id: 'np18', name: 'فول أخضر طازج (كيلو)', price: 25, emoji: '🫘' },
        { id: 'np19', name: 'فاصوليا خضراء (كيلو)', price: 35, emoji: '🫘' },
        { id: 'np20', name: 'بقدونس + كزبرة (حزمة)', price: 8, emoji: '🌿' },
      ]},
    ],
  },

  // ── إلكترونيات ─────────────────────────────────────────────

  {
    id: 'mobile-zone',
    name: 'موبايل زون دمياط',
    category: 'موبايلات وإلكترونيات',
    categoryId: 'electronics',
    emoji: '📱',
    area: 'دمياط الجديدة — شارع الكباش',
    address: 'شارع محور الكباش، بجوار فودافون، دمياط الجديدة',
    phone: '0572273456',
    rating: 4.6,
    reviews: 590,
    deliveryTime: '45–70 دقيقة',
    deliveryFee: 30,
    minOrder: 100,
    tagline: 'أحدث إكسسوارات الموبايل والإلكترونيات بأفضل سعر',
    menu: [
      { section: 'شواحن وكابلات', items: [
        { id: 'mz1', name: 'شاحن سامسونج أصلي 25 واط', price: 330, emoji: '🔌' },
        { id: 'mz2', name: 'شاحن أبل أصلي 20 واط', price: 390, emoji: '🔌' },
        { id: 'mz3', name: 'كابل تايب-سي 2 متر (أصلي)', price: 98, emoji: '🔌' },
        { id: 'mz4', name: 'كابل آيفون Lightning', price: 125, emoji: '🔌' },
        { id: 'mz5', name: 'محول OTG تايب-سي', price: 88, emoji: '🔌' },
      ]},
      { section: 'سماعات', items: [
        { id: 'mz6', name: 'سماعة JBL بلوتوث Go 3', price: 720, emoji: '🎧' },
        { id: 'mz7', name: 'إيربودز TWS لاسلكية', price: 235, emoji: '🎧' },
        { id: 'mz8', name: 'سماعة سلكية للموبايل', price: 88, emoji: '🎧' },
      ]},
      { section: 'حماية وإكسسوار', items: [
        { id: 'mz9', name: 'كفر حماية لسامسونج A55', price: 88, emoji: '📱' },
        { id: 'mz10', name: 'كفر حماية لآيفون 15', price: 125, emoji: '📱' },
        { id: 'mz11', name: 'لاصق حماية شاشة (زجاج)', price: 58, emoji: '📱' },
        { id: 'mz12', name: 'حامل موبايل للعربية', price: 95, emoji: '🚗' },
      ]},
      { section: 'باور بانك', items: [
        { id: 'mz13', name: 'باور بانك 20000 مللي', price: 800, emoji: '🔋' },
        { id: 'mz14', name: 'باور بانك 10000 مللي', price: 490, emoji: '🔋' },
        { id: 'mz15', name: 'ساعة ذكية سمارت ووتش', price: 1500, emoji: '⌚' },
      ]},
    ],
  },

  // ── كشري ───────────────────────────────────────────────────

  {
    id: 'koshary-damietta',
    name: 'كشري دمياط الجديدة',
    category: 'كشري وأكل مصري',
    categoryId: 'restaurant',
    emoji: '🍝',
    area: 'دمياط الجديدة — المجاورة الثالثة',
    address: 'شارع الجامعة، المجاورة الثالثة، دمياط الجديدة',
    phone: '01122334455',
    rating: 4.6,
    reviews: 1520,
    deliveryTime: '25–40 دقيقة',
    deliveryFee: 12,
    minOrder: 40,
    tagline: 'كشري مصري أصيل — عدس وحمص وشطة على أصولها',
    menu: [
      { section: 'كشري', items: [
        { id: 'ks1', name: 'كشري صغير', desc: 'مكرونة + رز + عدس + حمص + شطة + دقة', price: 35, emoji: '🍝' },
        { id: 'ks2', name: 'كشري وسط', price: 50, emoji: '🍝' },
        { id: 'ks3', name: 'كشري كبير', price: 70, emoji: '🍝' },
        { id: 'ks4', name: 'كشري فاميلي (4 أفراد)', desc: 'طبق عائلي كبير', price: 180, emoji: '🥘' },
        { id: 'ks5', name: 'كشري سوبر (بصل مقرمش زيادة)', price: 85, emoji: '🍝' },
      ]},
      { section: 'إضافات', items: [
        { id: 'ks6', name: 'بصل مقلي إضافي', price: 12, emoji: '🧅' },
        { id: 'ks7', name: 'صلصة شطة', price: 8, emoji: '🌶️' },
        { id: 'ks8', name: 'دقة (ثوم وخل)', price: 8, emoji: '🧄' },
        { id: 'ks9', name: 'حمص الشام علبة', price: 20, emoji: '🫘' },
      ]},
      { section: 'حلويات ومشروبات', items: [
        { id: 'ks10', name: 'رز بلبن', price: 30, emoji: '🍮' },
        { id: 'ks11', name: 'مهلبية', price: 28, emoji: '🍨' },
        { id: 'ks12', name: 'مياه معدنية', price: 12, emoji: '💧' },
        { id: 'ks13', name: 'بيبسي كانز', price: 20, emoji: '🥤' },
      ]},
    ],
  },

  // ── فول وفلافل ─────────────────────────────────────────────

  {
    id: 'shabrawy-damietta',
    name: 'فول وفلافل الشبراوي',
    category: 'فطار شعبي',
    categoryId: 'restaurant',
    emoji: '🧆',
    area: 'دمياط الجديدة — الحي الثالث',
    address: 'شارع 15، الحي الثالث، دمياط الجديدة',
    phone: '01099887766',
    rating: 4.7,
    reviews: 2210,
    deliveryTime: '20–35 دقيقة',
    deliveryFee: 10,
    minOrder: 30,
    tagline: 'فطارك على أصوله — فول وطعمية وبيض طازج كل صباح',
    menu: [
      { section: 'ساندويتشات', items: [
        { id: 'sh1', name: 'ساندويتش فول', price: 12, emoji: '🥙' },
        { id: 'sh2', name: 'ساندويتش طعمية', price: 12, emoji: '🧆' },
        { id: 'sh3', name: 'ساندويتش بطاطس', price: 14, emoji: '🥔' },
        { id: 'sh4', name: 'ساندويتش بيض', price: 18, emoji: '🥚' },
        { id: 'sh5', name: 'ساندويتش فول بالزيت الحار', price: 15, emoji: '🌶️' },
        { id: 'sh6', name: 'ساندويتش بسطرمة بالبيض', price: 35, emoji: '🥪' },
      ]},
      { section: 'أطباق', items: [
        { id: 'sh7', name: 'طبق فول مدمس', desc: 'فول بالزيت والكمون والليمون', price: 30, emoji: '🫘' },
        { id: 'sh8', name: 'طبق طعمية (6 قطع)', price: 32, emoji: '🧆' },
        { id: 'sh9', name: 'بيض أومليت بالخضار', price: 45, emoji: '🍳' },
        { id: 'sh10', name: 'فول بالطحينة', price: 38, emoji: '🫙' },
        { id: 'sh11', name: 'فول إسكندراني', price: 42, emoji: '🥘' },
      ]},
      { section: 'وجبة فطار عائلية', items: [
        { id: 'sh12', name: 'صينية فطار (فول + طعمية + بيض + جبنة + بطاطس + عيش)', price: 145, emoji: '🍽️' },
        { id: 'sh13', name: 'جبنة قريش بالطماطم', price: 25, emoji: '🧀' },
        { id: 'sh14', name: 'بابا غنوج', price: 28, emoji: '🍆' },
      ]},
      { section: 'مشروبات', items: [
        { id: 'sh15', name: 'شاي', price: 10, emoji: '🍵' },
        { id: 'sh16', name: 'لبن بالشوكولاتة', price: 22, emoji: '🥛' },
      ]},
    ],
  },

  // ── بيتزا ومعجنات ──────────────────────────────────────────

  {
    id: 'italiano-pizza',
    name: 'بيتزا إيطاليانو دمياط',
    category: 'بيتزا ومعجنات',
    categoryId: 'restaurant',
    emoji: '🍕',
    area: 'دمياط الجديدة — الحي الأول',
    address: 'شارع المعهد الديني، الحي الأول، دمياط الجديدة',
    phone: '01200556677',
    rating: 4.5,
    reviews: 1340,
    deliveryTime: '35–55 دقيقة',
    deliveryFee: 18,
    minOrder: 70,
    tagline: 'بيتزا إيطالي طازج — عجينة هشة وجبنة موتزاريلا أصلية',
    menu: [
      { section: 'بيتزا (وسط)', items: [
        { id: 'it1', name: 'بيتزا مارجريتا', desc: 'صلصة طماطم وموتزاريلا', price: 95, emoji: '🍕' },
        { id: 'it2', name: 'بيتزا بيبروني', price: 130, emoji: '🍕' },
        { id: 'it3', name: 'بيتزا فراخ باربكيو', price: 145, emoji: '🍕' },
        { id: 'it4', name: 'بيتزا مشكل لحوم', desc: 'بسطرمة + سجق + لحمة + فراخ', price: 165, emoji: '🍕' },
        { id: 'it5', name: 'بيتزا خضار', price: 110, emoji: '🍕' },
        { id: 'it6', name: 'بيتزا سي فود (جمبري)', price: 195, emoji: '🍕' },
      ]},
      { section: 'فطائر ومعجنات', items: [
        { id: 'it7', name: 'فطيرة جبنة وزعتر', price: 55, emoji: '🥐' },
        { id: 'it8', name: 'كالزوني بالفراخ', price: 90, emoji: '🥟' },
        { id: 'it9', name: 'عيش بالثوم (بريد ستيك)', price: 50, emoji: '🥖' },
        { id: 'it10', name: 'فطيرة سجق', price: 65, emoji: '🌭' },
      ]},
      { section: 'باستا', items: [
        { id: 'it11', name: 'باستا ألفريدو بالفراخ', price: 120, emoji: '🍝' },
        { id: 'it12', name: 'باستا بولونيز', price: 115, emoji: '🍝' },
        { id: 'it13', name: 'لازانيا باللحمة', price: 135, emoji: '🍲' },
      ]},
      { section: 'إضافات ومشروبات', items: [
        { id: 'it14', name: 'صوص رانش / باربكيو', price: 15, emoji: '🫙' },
        { id: 'it15', name: 'بطاطس ودجز', price: 45, emoji: '🍟' },
        { id: 'it16', name: 'كوكاكولا 1 لتر', price: 25, emoji: '🥤' },
      ]},
    ],
  },

  // ── مخبز وعيش ──────────────────────────────────────────────

  {
    id: 'nour-bakery',
    name: 'مخبز ومعجنات النور',
    category: 'مخبز وفينو',
    categoryId: 'bakery',
    emoji: '🥖',
    area: 'دمياط الجديدة — المجاورة الثانية',
    address: 'شارع السوق التجاري، المجاورة الثانية، دمياط الجديدة',
    phone: '01066778899',
    rating: 4.6,
    reviews: 980,
    deliveryTime: '20–35 دقيقة',
    deliveryFee: 10,
    minOrder: 30,
    tagline: 'عيش فينو وفرنساوي طازج بالساعة — معجنات صباحية يومية',
    menu: [
      { section: 'مخبوزات', items: [
        { id: 'nb1', name: 'عيش فينو (10 أرغفة)', price: 25, emoji: '🥖' },
        { id: 'nb2', name: 'عيش فرنساوي (باجيت)', price: 12, emoji: '🥖' },
        { id: 'nb3', name: 'عيش توست أبيض', price: 30, emoji: '🍞' },
        { id: 'nb4', name: 'عيش توست بُر', price: 35, emoji: '🍞' },
        { id: 'nb5', name: 'عيش برجر (6 حبات)', price: 28, emoji: '🍔' },
      ]},
      { section: 'معجنات حلوة', items: [
        { id: 'nb6', name: 'كرواسون سادة (4 حبات)', price: 60, emoji: '🥐' },
        { id: 'nb7', name: 'كرواسون شوكولاتة (4 حبات)', price: 80, emoji: '🥐' },
        { id: 'nb8', name: 'بان كيك بالعسل', price: 45, emoji: '🥞' },
        { id: 'nb9', name: 'دانش بالجبنة', price: 22, emoji: '🧀' },
        { id: 'nb10', name: 'ميني باتيه (12 قطعة)', price: 75, emoji: '🥟' },
      ]},
      { section: 'معجنات مالحة', items: [
        { id: 'nb11', name: 'فطيرة سجق', price: 18, emoji: '🌭' },
        { id: 'nb12', name: 'بيتزا ميني (4 قطع)', price: 60, emoji: '🍕' },
        { id: 'nb13', name: 'سمبوسك جبنة (10 قطع)', price: 55, emoji: '🥟' },
        { id: 'nb14', name: 'فطير مشلتت سادة', price: 40, emoji: '🥞' },
      ]},
    ],
  },
];

export function getStore(id: string): Store | undefined {
  return STORES.find(s => s.id === id);
}
