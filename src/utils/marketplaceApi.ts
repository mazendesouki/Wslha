// سوق المستعمل — Supabase-backed marketplace API

const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
const SB_H   = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' };

export interface MarketItem {
  id: string;
  seller_phone: string;
  seller_type: 'customer' | 'merchant';
  title: string;
  description?: string;
  category: string;
  condition: 'new' | 'like_new' | 'used' | 'fair';
  price: number;
  quantity: number;
  city?: string;
  area?: string;
  images: string[];
  contact_phone: string;
  whatsapp: boolean;
  status: 'active' | 'sold' | 'removed' | 'under_review';
  reports_count: number;
  views: number;
  created_at: string;
}

export const CATEGORIES: { id: string; label: string; emoji: string }[] = [
  { id: 'electronics', label: 'إلكترونيات وموبايلات', emoji: '📱' },
  { id: 'furniture',   label: 'أثاث ومنزل',           emoji: '🛋️' },
  { id: 'cars',        label: 'سيارات ومركبات',        emoji: '🚗' },
  { id: 'fashion',     label: 'ملابس وإكسسوارات',       emoji: '👕' },
  { id: 'appliances',  label: 'أجهزة كهربائية',        emoji: '🔌' },
  { id: 'kids',        label: 'مستلزمات أطفال',        emoji: '🧸' },
  { id: 'books',       label: 'كتب وقرطاسية',          emoji: '📚' },
  { id: 'sports',      label: 'رياضة وهوايات',         emoji: '⚽' },
  { id: 'other',       label: 'أخرى',                  emoji: '📦' },
];

export const CONDITIONS: Record<string, string> = {
  new: 'جديد',
  like_new: 'كالجديد',
  used: 'مستعمل بحالة جيدة',
  fair: 'مستعمل - يحتاج صيانة',
};

async function sb<T>(path: string, init?: RequestInit): Promise<T | null> {
  try {
    const res = await fetch(`${SB_URL}/rest/v1/${path}`, { ...init, headers: { ...SB_H, ...(init?.headers || {}) } });
    if (!res.ok) return null;
    const text = await res.text();
    return text ? JSON.parse(text) : (null as any);
  } catch { return null; }
}

export async function fetchItems(filters: { category?: string; city?: string; search?: string } = {}): Promise<MarketItem[]> {
  const parts = ['status=eq.active', 'order=created_at.desc', 'limit=200'];
  if (filters.category) parts.push(`category=eq.${encodeURIComponent(filters.category)}`);
  if (filters.city) parts.push(`city=eq.${encodeURIComponent(filters.city)}`);
  const rows = await sb<MarketItem[]>(`marketplace_items?${parts.join('&')}&select=*`);
  let items = rows ?? [];
  if (filters.search) {
    const q = filters.search.toLowerCase();
    items = items.filter(i => i.title.toLowerCase().includes(q) || (i.description || '').toLowerCase().includes(q));
  }
  return items;
}

export async function fetchItem(id: string): Promise<MarketItem | null> {
  const rows = await sb<MarketItem[]>(`marketplace_items?id=eq.${encodeURIComponent(id)}&select=*&limit=1`);
  return rows?.[0] ?? null;
}

export async function incrementViews(id: string, currentViews: number): Promise<void> {
  // Best-effort, non-critical — silently ignore failures (views isn't security-sensitive).
  await sb(`marketplace_items?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ views: currentViews + 1 }),
  }).catch(() => {});
}

export async function createItem(payload: {
  seller_phone: string; title: string; description?: string; category: string;
  condition: string; price: number; quantity?: number; city?: string; area?: string;
  images: string[]; contact_phone: string; whatsapp: boolean;
}): Promise<MarketItem | null> {
  const rows = await sb<MarketItem[]>('marketplace_items', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(payload),
  });
  return rows?.[0] ?? null;
}

export async function reportItem(itemId: string, reporterPhone: string, reason: string): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/rpc/report_marketplace_item`, {
    method: 'POST', headers: SB_H,
    body: JSON.stringify({ p_item_id: itemId, p_reporter_phone: reporterPhone || null, p_reason: reason }),
  });
  return res.ok;
}

export async function updateOwnItemStatus(phone: string, itemId: string, status: 'sold' | 'removed'): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/rpc/update_own_marketplace_item`, {
    method: 'POST', headers: SB_H,
    body: JSON.stringify({ p_phone: phone, p_item_id: itemId, p_status: status }),
  });
  if (!res.ok) return false;
  return (await res.json()) === true;
}

export async function requestDelivery(itemId: string, buyer: { phone: string; name: string; address: string }): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/rpc/request_marketplace_delivery`, {
    method: 'POST', headers: SB_H,
    body: JSON.stringify({ p_item_id: itemId, p_buyer_phone: buyer.phone, p_buyer_name: buyer.name, p_buyer_address: buyer.address }),
  });
  return res.ok;
}

export async function uploadImage(file: File): Promise<string | null> {
  try {
    const path = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
    const res = await fetch(`${SB_URL}/storage/v1/object/marketplace/${path}`, {
      method: 'POST',
      headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': file.type },
      body: file,
    });
    if (!res.ok) return null;
    return `${SB_URL}/storage/v1/object/public/marketplace/${path}`;
  } catch { return null; }
}
