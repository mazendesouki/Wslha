export interface NavLink {
  label: string;
  href: string;
  page: string;
}

export const NAV_LINKS: NavLink[] = [
  { label: 'الرئيسية',     href: '/',          page: 'home'     },
  { label: 'المتاجر',      href: '/stores',     page: 'stores'   },
  { label: 'مشاوير',       href: '/rides',      page: 'rides'    },
  { label: 'توصيل المطار', href: '/airport',    page: 'airport'  },
  { label: 'خدماتنا',      href: '/services',   page: 'services' },
  { label: 'من نحن',       href: '/about',      page: 'about'    },
  { label: 'تواصل معنا',   href: '/contact',    page: 'contact'  },
];

export const FOOTER_LINKS = {
  quick: [
    { label: 'الرئيسية',    href: '/'        },
    { label: 'من نحن',      href: '/about'    },
    { label: 'مشاوير',      href: '/rides'    },
    { label: 'تتبع الطلب',  href: '/track'    },
    { label: 'تواصل معنا',  href: '/contact'  },
  ],
  services: [
    { label: 'المتاجر المحلية', href: '/stores'   },
    { label: 'توصيل المطار',   href: '/airport'  },
    { label: 'مشاوير دمياط',   href: '/rides'    },
    { label: 'الأسعار',        href: '/services#pricing' },
  ],
  contact: [
    { label: '📞 0020 1102 667324',   href: 'tel:+201102667324'              },
    { label: '✉️ info@wslha.co',       href: 'mailto:info@wslha.co'           },
    { label: '💬 واتساب',              href: 'https://wa.me/201102667324'     },
  ],
};
