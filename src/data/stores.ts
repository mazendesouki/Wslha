// Local merchants in Damietta governorate with their product catalogs.
// Prices are in EGP (ج.م). Pure data — consumed by /stores and /store/[id].

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
  category: string;        // display category
  categoryId: string;      // for filtering
  emoji: string;
  area: string;
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
  {
    id: 'bahr-seafood',
    name: 'مطعم البحر للأسماك',
    category: 'مأكولات بحرية',
    categoryId: 'restaurant',
    emoji: '🦐',
    area: 'رأس البر',
    rating: 4.8,
    reviews: 1240,
    deliveryTime: '40–55 دقيقة',
    deliveryFee: 20,
    minOrder: 100,
    tagline: 'أطيب أسماك دمياط الطازجة على باب بيتك',
    menu: [
      { section: 'أطباق رئيسية', items: [
        { id: 'b1', name: 'صينية جمبري مشوي', desc: 'جمبري طازج مع الأرز والسلطة', price: 180, emoji: '🦐' },
        { id: 'b2', name: 'سمك بلطي مقلي', desc: 'بلطي طازج مع طحينة وأرز صيادية', price: 120, emoji: '🐟' },
        { id: 'b3', name: 'كاليماري مقلي', desc: 'حلقات كاليماري مقرمشة', price: 150, emoji: '🦑' },
        { id: 'b4', name: 'سمك مشوي بالفرن', desc: 'مشوي مع الخضار والليمون', price: 140, emoji: '🐠' },
      ]},
      { section: 'إضافات', items: [
        { id: 'b5', name: 'أرز صيادية', price: 25, emoji: '🍚' },
        { id: 'b6', name: 'سلطة طحينة', price: 15, emoji: '🥗' },
        { id: 'b7', name: 'عيش بلدي (5 أرغفة)', price: 10, emoji: '🫓' },
      ]},
      { section: 'مشروبات', items: [
        { id: 'b8', name: 'عصير ليمون نعناع', price: 20, emoji: '🍋' },
        { id: 'b9', name: 'مياه معدنية', price: 8, emoji: '💧' },
      ]},
    ],
  },
  {
    id: 'pizza-corner',
    name: 'ركن البيتزا',
    category: 'بيتزا ووجبات سريعة',
    categoryId: 'restaurant',
    emoji: '🍕',
    area: 'دمياط الجديدة',
    rating: 4.6,
    reviews: 890,
    deliveryTime: '30–45 دقيقة',
    deliveryFee: 15,
    minOrder: 60,
    tagline: 'بيتزا إيطالية أصلية وعجينة طازجة يومياً',
    menu: [
      { section: 'بيتزا', items: [
        { id: 'p1', name: 'بيتزا مارجريتا', desc: 'جبنة موزاريلا وصلصة طماطم', price: 75, emoji: '🍕' },
        { id: 'p2', name: 'بيتزا بيبروني', desc: 'بيبروني ومزيج أجبان', price: 95, emoji: '🍕' },
        { id: 'p3', name: 'بيتزا فراخ باربكيو', desc: 'فراخ مشوية وصوص باربكيو', price: 110, emoji: '🍕' },
        { id: 'p4', name: 'بيتزا سي فود', desc: 'جمبري وكاليماري وأجبان', price: 130, emoji: '🍕' },
      ]},
      { section: 'برجر وسندويتشات', items: [
        { id: 'p5', name: 'تشيز برجر دبل', price: 85, emoji: '🍔' },
        { id: 'p6', name: 'كريسبي تشيكن', price: 70, emoji: '🍗' },
      ]},
      { section: 'إضافات ومشروبات', items: [
        { id: 'p7', name: 'بطاطس مقلية', price: 25, emoji: '🍟' },
        { id: 'p8', name: 'بيبسي كانز', price: 12, emoji: '🥤' },
      ]},
    ],
  },
  {
    id: 'koshari-tahrir',
    name: 'كشري التحرير',
    category: 'مأكولات شعبية',
    categoryId: 'restaurant',
    emoji: '🍚',
    area: 'دمياط',
    rating: 4.7,
    reviews: 2100,
    deliveryTime: '25–35 دقيقة',
    deliveryFee: 12,
    minOrder: 40,
    tagline: 'أشهر كشري في دمياط منذ 1995',
    menu: [
      { section: 'الكشري', items: [
        { id: 'k1', name: 'كشري وسط', desc: 'عدس ومكرونة وأرز وحمص', price: 30, emoji: '🍚' },
        { id: 'k2', name: 'كشري كبير', desc: 'حجم عائلي', price: 45, emoji: '🍚' },
        { id: 'k3', name: 'كشري سوبر بالزيادة', desc: 'دبل بصل وحمص وصلصة', price: 55, emoji: '🍚' },
      ]},
      { section: 'إضافات', items: [
        { id: 'k4', name: 'بصل مقلي إضافي', price: 8, emoji: '🧅' },
        { id: 'k5', name: 'صلصة حارة', price: 5, emoji: '🌶️' },
        { id: 'k6', name: 'رز بلبن', price: 20, emoji: '🍮' },
      ]},
    ],
  },
  {
    id: 'fresh-market',
    name: 'فريش ماركت',
    category: 'سوبر ماركت',
    categoryId: 'grocery',
    emoji: '🛒',
    area: 'دمياط الجديدة',
    rating: 4.5,
    reviews: 670,
    deliveryTime: '45–60 دقيقة',
    deliveryFee: 18,
    minOrder: 80,
    tagline: 'كل احتياجات البيت توصلك لباب الشقة',
    menu: [
      { section: 'ألبان وأجبان', items: [
        { id: 'f1', name: 'لبن جهينة 1 لتر', price: 38, emoji: '🥛' },
        { id: 'f2', name: 'جبنة بيضاء (½ كيلو)', price: 65, emoji: '🧀' },
        { id: 'f3', name: 'زبادي (عبوة 6)', price: 42, emoji: '🥛' },
      ]},
      { section: 'بقالة', items: [
        { id: 'f4', name: 'أرز مصري (5 كيلو)', price: 130, emoji: '🍚' },
        { id: 'f5', name: 'زيت عباد الشمس (2.25 لتر)', price: 145, emoji: '🛢️' },
        { id: 'f6', name: 'سكر (كيلو)', price: 32, emoji: '🍬' },
        { id: 'f7', name: 'مكرونة (½ كيلو)', price: 18, emoji: '🍝' },
      ]},
      { section: 'منظفات', items: [
        { id: 'f8', name: 'مسحوق غسيل (3 كيلو)', price: 160, emoji: '🧼' },
        { id: 'f9', name: 'سائل أطباق', price: 45, emoji: '🧴' },
      ]},
    ],
  },
  {
    id: 'shifa-pharmacy',
    name: 'صيدلية الشفاء',
    category: 'صيدلية',
    categoryId: 'pharmacy',
    emoji: '💊',
    area: 'دمياط',
    rating: 4.9,
    reviews: 1530,
    deliveryTime: '20–30 دقيقة',
    deliveryFee: 10,
    minOrder: 0,
    tagline: 'أدويتك ومستلزماتك الطبية بسرعة وأمان',
    menu: [
      { section: 'أدوية بدون روشتة', items: [
        { id: 's1', name: 'بنادول إكسترا', price: 35, emoji: '💊' },
        { id: 's2', name: 'فيتامين سي فوار', price: 55, emoji: '🍊' },
        { id: 's3', name: 'كمادات وشاش طبي', price: 40, emoji: '🩹' },
      ]},
      { section: 'العناية والصحة', items: [
        { id: 's4', name: 'جل معقم لليدين', price: 30, emoji: '🧴' },
        { id: 's5', name: 'كمامات طبية (50)', price: 60, emoji: '😷' },
        { id: 's6', name: 'جهاز قياس ضغط', price: 650, emoji: '🩺' },
      ]},
      { section: 'مستلزمات الأطفال', items: [
        { id: 's7', name: 'حفاضات أطفال (مقاس 3)', price: 220, emoji: '🍼' },
        { id: 's8', name: 'لبن أطفال', price: 180, emoji: '🍼' },
      ]},
    ],
  },
  {
    id: 'sweet-house',
    name: 'بيت الحلويات',
    category: 'حلويات شرقية وغربية',
    categoryId: 'bakery',
    emoji: '🍰',
    area: 'دمياط الجديدة',
    rating: 4.8,
    reviews: 980,
    deliveryTime: '35–50 دقيقة',
    deliveryFee: 15,
    minOrder: 50,
    tagline: 'دمياط مدينة الحلويات — اطلب الأصالة',
    menu: [
      { section: 'حلويات شرقية', items: [
        { id: 'sw1', name: 'بقلاوة (كيلو)', price: 180, emoji: '🥮' },
        { id: 'sw2', name: 'كنافة بالقشطة', price: 120, emoji: '🍮' },
        { id: 'sw3', name: 'بسبوسة بالقشطة', price: 90, emoji: '🍰' },
      ]},
      { section: 'كيك وجاتوه', items: [
        { id: 'sw4', name: 'تورتة شوكولاتة', price: 250, emoji: '🎂' },
        { id: 'sw5', name: 'قطع جاتوه (6)', price: 150, emoji: '🧁' },
      ]},
      { section: 'مخبوزات', items: [
        { id: 'sw6', name: 'كرواسون بالزبدة (4)', price: 80, emoji: '🥐' },
        { id: 'sw7', name: 'فطير مشلتت', price: 70, emoji: '🥞' },
      ]},
    ],
  },
  {
    id: 'green-produce',
    name: 'الخضار الطازج',
    category: 'خضار وفاكهة',
    categoryId: 'produce',
    emoji: '🥬',
    area: 'كفر سعد',
    rating: 4.4,
    reviews: 410,
    deliveryTime: '40–55 دقيقة',
    deliveryFee: 15,
    minOrder: 50,
    tagline: 'من المزرعة لبيتك — طازج كل يوم',
    menu: [
      { section: 'خضار', items: [
        { id: 'g1', name: 'طماطم (كيلو)', price: 18, emoji: '🍅' },
        { id: 'g2', name: 'بطاطس (كيلو)', price: 16, emoji: '🥔' },
        { id: 'g3', name: 'بصل (كيلو)', price: 14, emoji: '🧅' },
        { id: 'g4', name: 'خيار (كيلو)', price: 12, emoji: '🥒' },
      ]},
      { section: 'فاكهة', items: [
        { id: 'g5', name: 'موز (كيلو)', price: 28, emoji: '🍌' },
        { id: 'g6', name: 'تفاح (كيلو)', price: 55, emoji: '🍎' },
        { id: 'g7', name: 'برتقال (كيلو)', price: 22, emoji: '🍊' },
        { id: 'g8', name: 'مانجو (كيلو)', price: 60, emoji: '🥭' },
      ]},
    ],
  },
  {
    id: 'techzone',
    name: 'تك زون',
    category: 'إلكترونيات وموبايلات',
    categoryId: 'electronics',
    emoji: '📱',
    area: 'دمياط الجديدة',
    rating: 4.6,
    reviews: 320,
    deliveryTime: '50–70 دقيقة',
    deliveryFee: 25,
    minOrder: 100,
    tagline: 'أحدث الأجهزة والإكسسوارات بأفضل الأسعار',
    menu: [
      { section: 'إكسسوارات', items: [
        { id: 't1', name: 'شاحن سريع 25 واط', price: 280, emoji: '🔌' },
        { id: 't2', name: 'سماعة بلوتوث', price: 450, emoji: '🎧' },
        { id: 't3', name: 'كابل تايب سي', price: 90, emoji: '🔋' },
        { id: 't4', name: 'جراب موبايل', price: 120, emoji: '📱' },
      ]},
      { section: 'أجهزة', items: [
        { id: 't5', name: 'باور بانك 20000', price: 650, emoji: '🔋' },
        { id: 't6', name: 'ساعة ذكية', price: 1200, emoji: '⌚' },
      ]},
    ],
  },
];

export function getStore(id: string): Store | undefined {
  return STORES.find(s => s.id === id);
}
