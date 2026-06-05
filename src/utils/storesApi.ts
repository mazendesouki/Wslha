// Supabase-backed stores API — fetches stores, sections, products live
// Falls back to static STORES data if Supabase is unavailable

const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
const SB_H   = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' };

export interface StoreRow {
  id: string;
  name: string;
  category: string;
  category_id: string;
  emoji: string;
  area: string;
  phone?: string;
  address?: string;
  owner_phone?: string;
  rating: number;
  reviews: number;
  delivery_time: string;
  delivery_fee: number;
  min_order: number;
  tagline: string;
  is_open: boolean;
  is_active: boolean;
}

export interface SectionRow {
  id: string;
  store_id: string;
  name: string;
  sort_order: number;
}

export interface ProductRow {
  id: string;
  store_id: string;
  section_id: string;
  name: string;
  description?: string;
  price: number;
  emoji: string;
  is_available: boolean;
  sort_order: number;
}

async function sb<T>(path: string, opts?: RequestInit): Promise<T | null> {
  try {
    const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
      ...opts,
      headers: { ...SB_H, ...(opts?.headers as Record<string, string> || {}) },
    });
    if (!res.ok) return null;
    return await res.json() as T;
  } catch { return null; }
}

// ── Store CRUD ──

export async function fetchStores(): Promise<StoreRow[]> {
  return await sb<StoreRow[]>('stores?is_active=eq.true&order=name') ?? [];
}

export async function fetchStore(id: string): Promise<StoreRow | null> {
  const rows = await sb<StoreRow[]>(`stores?id=eq.${encodeURIComponent(id)}&limit=1`);
  return rows?.[0] ?? null;
}

export async function fetchMerchantStore(ownerPhone: string): Promise<StoreRow | null> {
  const rows = await sb<StoreRow[]>(`stores?owner_phone=eq.${encodeURIComponent(ownerPhone)}&limit=1`);
  return rows?.[0] ?? null;
}

export async function upsertStore(store: Partial<StoreRow> & { id: string }): Promise<StoreRow | null> {
  const rows = await sb<StoreRow[]>('stores', {
    method: 'POST',
    headers: { Prefer: 'return=representation,resolution=merge-duplicates' },
    body: JSON.stringify(store),
  });
  return Array.isArray(rows) ? rows[0] : null;
}

export async function patchStore(id: string, patch: Partial<StoreRow>): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/stores?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { ...SB_H, Prefer: 'return=minimal' },
    body: JSON.stringify(patch),
  });
  return res.ok;
}

// ── Sections CRUD ──

export async function fetchSections(storeId: string): Promise<SectionRow[]> {
  return await sb<SectionRow[]>(`menu_sections?store_id=eq.${encodeURIComponent(storeId)}&order=sort_order`) ?? [];
}

export async function createSection(storeId: string, name: string, sortOrder = 0): Promise<SectionRow | null> {
  const rows = await sb<SectionRow[]>('menu_sections', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ store_id: storeId, name, sort_order: sortOrder }),
  });
  return Array.isArray(rows) ? rows[0] : null;
}

export async function patchSection(id: string, patch: Partial<SectionRow>): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/menu_sections?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { ...SB_H, Prefer: 'return=minimal' },
    body: JSON.stringify(patch),
  });
  return res.ok;
}

export async function deleteSection(id: string): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/menu_sections?id=eq.${encodeURIComponent(id)}`, {
    method: 'DELETE', headers: SB_H,
  });
  return res.ok;
}

// ── Products CRUD ──

export async function fetchProducts(storeId: string): Promise<ProductRow[]> {
  return await sb<ProductRow[]>(`products?store_id=eq.${encodeURIComponent(storeId)}&order=sort_order`) ?? [];
}

export async function searchProducts(query: string): Promise<(ProductRow & { store_name?: string })[]> {
  if (!query.trim()) return [];
  const q = encodeURIComponent(`%${query.trim()}%`);
  return await sb<ProductRow[]>(`products?name=ilike.${q}&is_available=eq.true&limit=30&order=name`) ?? [];
}

export async function createProduct(p: Omit<ProductRow, 'id'>): Promise<ProductRow | null> {
  const rows = await sb<ProductRow[]>('products', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(p),
  });
  return Array.isArray(rows) ? rows[0] : null;
}

export async function patchProduct(id: string, patch: Partial<ProductRow>): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/products?id=eq.${encodeURIComponent(id)}`, {
    method: 'PATCH',
    headers: { ...SB_H, Prefer: 'return=minimal' },
    body: JSON.stringify(patch),
  });
  return res.ok;
}

export async function deleteProduct(id: string): Promise<boolean> {
  const res = await fetch(`${SB_URL}/rest/v1/products?id=eq.${encodeURIComponent(id)}`, {
    method: 'DELETE', headers: SB_H,
  });
  return res.ok;
}

// ── Store orders stats ──
export async function fetchStoreStats(storeId: string) {
  const today = new Date().toISOString().split('T')[0];
  const [todayOrders, allOrders] = await Promise.all([
    sb<any[]>(`orders?store_id=eq.${encodeURIComponent(storeId)}&created_at=gte.${today}&select=total`),
    sb<any[]>(`orders?store_id=eq.${encodeURIComponent(storeId)}&select=total,status&order=created_at.desc&limit=20`),
  ]);
  const todayRevenue = (todayOrders ?? []).reduce((s: number, o: any) => s + (o.total || 0), 0);
  return {
    todayOrders: (todayOrders ?? []).length,
    todayRevenue,
    recentOrders: allOrders ?? [],
  };
}
