const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
export const SB_H: Record<string, string> = {
  apikey: SB_KEY,
  Authorization: `Bearer ${SB_KEY}`,
  'Content-Type': 'application/json',
};

async function sbGet(path: string) {
  const ctrl = new AbortController();
  const tid  = setTimeout(() => ctrl.abort(), 8000);
  try {
    const res = await fetch(`${SB_URL}/rest/v1/${path}`, { headers: SB_H, signal: ctrl.signal });
    clearTimeout(tid);
    if (!res.ok) return null;
    return await res.json();
  } catch { return null; }
}
async function sbPatch(path: string, body: object) {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method: 'PATCH', headers: { ...SB_H, Prefer: 'return=minimal' }, body: JSON.stringify(body),
  });
  return res.ok;
}
async function sbPost(path: string, body: object) {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method: 'POST', headers: { ...SB_H, Prefer: 'return=minimal' }, body: JSON.stringify(body),
  });
  return res.ok;
}
async function sbDelete(path: string) {
  const res = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method: 'DELETE', headers: SB_H,
  });
  return res.ok;
}

// ── Upload file to Supabase Storage ───────────────────────────
export async function uploadDocument(file: File, folder: string): Promise<string | null> {
  const ext  = file.name.split('.').pop() || 'jpg';
  const name = `${folder}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;
  const res  = await fetch(`${SB_URL}/storage/v1/object/documents/${name}`, {
    method: 'POST',
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': file.type },
    body: file,
  });
  if (!res.ok) return null;
  return `${SB_URL}/storage/v1/object/public/documents/${name}`;
}

// ── Admin stats ────────────────────────────────────────────────
export async function getAdminStats() {
  const [users, orders, rides, stores, driverApps, merchantApps] = await Promise.all([
    sbGet('accounts?select=phone,role,status,created_at'),
    sbGet('orders?select=id,status,total,created_at&order=created_at.desc&limit=200'),
    sbGet('rides?select=id,status,base_fare,created_at&order=created_at.desc&limit=200'),
    sbGet('stores?select=id,is_active,is_open'),
    sbGet('driver_applications?select=id,status&status=eq.pending'),
    sbGet('merchant_applications?select=id,status&status=eq.pending'),
  ]);
  const today = new Date().toISOString().slice(0, 10);
  const todayOrders = (orders || []).filter((o: any) => (o.created_at || '').startsWith(today));
  const todayRevenue = todayOrders
    .filter((o: any) => o.status === 'delivered')
    .reduce((s: number, o: any) => s + (Number(o.total) || 0), 0);
  return {
    totalUsers:       (users  || []).length,
    totalCustomers:   (users  || []).filter((u: any) => u.role === 'customer').length,
    totalDrivers:     (users  || []).filter((u: any) => u.role === 'driver').length,
    totalAdmins:      (users  || []).filter((u: any) => u.role === 'admin').length,
    totalOrders:      (orders || []).length,
    todayOrders:      todayOrders.length,
    todayRevenue,
    totalRides:       (rides  || []).length,
    activeStores:     (stores || []).filter((s: any) => s.is_active).length,
    totalStores:      (stores || []).length,
    pendingDrivers:   (driverApps   || []).length,
    pendingMerchants: (merchantApps || []).length,
  };
}

// ── Users ──────────────────────────────────────────────────────
export const getAllUsers    = () => sbGet('accounts?select=id,phone,name,role,city,created_at,email,username,status,auth_user_id&order=created_at.desc&limit=500');
export const updateUserStatus = (phone: string, status: string) =>
  sbPatch(`accounts?phone=eq.${encodeURIComponent(phone)}`, { status });
export const updateUserRole = (phone: string, role: string) =>
  sbPatch(`accounts?phone=eq.${encodeURIComponent(phone)}`, { role });
export const deleteUser = (phone: string) =>
  sbDelete(`accounts?phone=eq.${encodeURIComponent(phone)}`);

// ── Driver applications ─────────────────────────────────────────
export const getDriverApplications = () =>
  sbGet('driver_applications?select=*&order=created_at.desc&limit=200');
export const getDriverApplication  = (phone: string) =>
  sbGet(`driver_applications?phone=eq.${encodeURIComponent(phone)}&select=*&limit=1`);
export const submitDriverApplication = (data: object) =>
  sbPost('driver_applications', data);
export const updateDriverApplication = (id: string, data: object) =>
  sbPatch(`driver_applications?id=eq.${encodeURIComponent(id)}`, data);

export async function approveDriver(phone: string, adminPhone: string) {
  const now = new Date().toISOString();
  const appOk = await sbPatch(
    `driver_applications?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'approved', reviewed_by: adminPhone, reviewed_at: now }
  );
  const accOk = await sbPatch(
    `accounts?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'approved', role: 'driver' }
  );
  return appOk && accOk;
}

export async function rejectDriver(phone: string, adminPhone: string, reason: string) {
  const now = new Date().toISOString();
  const appOk = await sbPatch(
    `driver_applications?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'rejected', reviewed_by: adminPhone, reviewed_at: now, rejection_reason: reason }
  );
  const accOk = await sbPatch(
    `accounts?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'rejected' }
  );
  return appOk && accOk;
}

// ── Merchant applications ──────────────────────────────────────
export const getMerchantApplications = () =>
  sbGet('merchant_applications?select=*&order=created_at.desc&limit=200');
export const getMerchantApplication  = (phone: string) =>
  sbGet(`merchant_applications?phone=eq.${encodeURIComponent(phone)}&select=*&limit=1`);
export const submitMerchantApplication = (data: object) =>
  sbPost('merchant_applications', data);
export const updateMerchantApplication = (id: string, data: object) =>
  sbPatch(`merchant_applications?id=eq.${encodeURIComponent(id)}`, data);

export async function approveMerchant(phone: string, adminPhone: string) {
  const now = new Date().toISOString();
  const appOk = await sbPatch(
    `merchant_applications?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'approved', reviewed_by: adminPhone, reviewed_at: now }
  );
  const accOk = await sbPatch(
    `accounts?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'approved' }
  );
  return appOk && accOk;
}

export async function rejectMerchant(phone: string, adminPhone: string, reason: string) {
  const now = new Date().toISOString();
  const appOk = await sbPatch(
    `merchant_applications?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'rejected', reviewed_by: adminPhone, reviewed_at: now, rejection_reason: reason }
  );
  const accOk = await sbPatch(
    `accounts?phone=eq.${encodeURIComponent(phone)}`,
    { status: 'rejected' }
  );
  return appOk && accOk;
}

// ── Orders ─────────────────────────────────────────────────────
export const getAllOrders = () =>
  sbGet('orders?select=*&order=created_at.desc&limit=500');
export const updateOrderStatus = (id: string, status: string) =>
  sbPatch(`orders?id=eq.${encodeURIComponent(id)}`, { status });
export const deleteOrder = (id: string) =>
  sbDelete(`orders?id=eq.${encodeURIComponent(id)}`);

// ── Rides ──────────────────────────────────────────────────────
export const getAllRides = () =>
  sbGet('rides?select=*&order=created_at.desc&limit=500');
export const updateRideStatus = (id: string, status: string) =>
  sbPatch(`rides?id=eq.${encodeURIComponent(id)}`, { status });

// ── Stores ─────────────────────────────────────────────────────
export const getAllStores = () =>
  sbGet('stores?select=*&order=created_at.desc&limit=200');
export const toggleStore = (id: string, is_active: boolean) =>
  sbPatch(`stores?id=eq.${encodeURIComponent(id)}`, { is_active });
export const deleteStore = (id: string) =>
  sbDelete(`stores?id=eq.${encodeURIComponent(id)}`);
