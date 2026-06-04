// Client-side shopping cart (localStorage). Single-store at a time, like
// typical food-delivery apps. Consumed by /store/[id].

export interface CartItem {
  id: string;
  name: string;
  price: number;
  emoji: string;
  qty: number;
}

export interface Cart {
  storeId: string;
  storeName: string;
  deliveryFee: number;
  minOrder: number;
  items: CartItem[];
}

const KEY = 'wslha_cart';

export function getCart(): Cart | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function saveCart(cart: Cart | null): void {
  try {
    if (cart && cart.items.length) localStorage.setItem(KEY, JSON.stringify(cart));
    else localStorage.removeItem(KEY);
  } catch { /* storage unavailable */ }
}

export function cartCount(cart: Cart | null): number {
  return cart ? cart.items.reduce((n, it) => n + it.qty, 0) : 0;
}

export function cartSubtotal(cart: Cart | null): number {
  return cart ? cart.items.reduce((n, it) => n + it.qty * it.price, 0) : 0;
}
