export interface NavLink {
  label: string;
  href: string;
  page: string;
}

export const NAV_LINKS: NavLink[] = [
  { label: 'الرئيسية',       href: '/',                    page: 'home'     },
  { label: 'خدماتنا',        href: '/services',             page: 'services' },
  { label: 'الأسعار',        href: '/services#pricing',     page: 'pricing'  },
  { label: 'طلب توصيل',      href: '/order',                page: 'order'    },
  { label: 'طلباتي',         href: '/orders',               page: 'orders'   },
  { label: 'تتبع الطلب',     href: '/track',                page: 'track'    },
  { label: 'من نحن',         href: '/about',                page: 'about'    },
  { label: 'تواصل معنا',     href: '/contact',              page: 'contact'  },
];

export const FOOTER_LINKS = {
  quick: [
    { label: 'الرئيسية',    href: '/'        },
    { label: 'من نحن',      href: '/about'    },
    { label: 'طلب توصيل',   href: '/order'    },
    { label: 'تتبع الطلب',  href: '/track'    },
    { label: 'تواصل معنا',  href: '/contact'  },
  ],
  services: [
    { label: 'توصيل محلي',    href: '/services#local'    },
    { label: 'توصيل مطار',   href: '/services#airport'  },
    { label: 'المتاجر الشريكة', href: '/services#partners' },
    { label: 'الأسعار',      href: '/services#pricing'  },
  ],
  contact: [
    { label: '📞 920-000-000',     href: 'tel:+218910000000'     },
    { label: '✉️ info@wslha.co',   href: 'mailto:info@wslha.co' },
    { label: '💬 واتساب',          href: 'https://wa.me/218910000000' },
  ],
};
