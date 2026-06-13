-- ══════════════════════════════════════════════════════════════
-- وصّلها — Supabase RLS Policies
-- Run this in Supabase → SQL Editor
-- ══════════════════════════════════════════════════════════════

-- ── accounts ─────────────────────────────────────────────────
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_insert_account" ON accounts;
CREATE POLICY "allow_anon_insert_account" ON accounts FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "allow_anon_select_account" ON accounts;
CREATE POLICY "allow_anon_select_account" ON accounts FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_anon_update_account" ON accounts;
CREATE POLICY "allow_anon_update_account" ON accounts FOR UPDATE USING (true) WITH CHECK (true);


-- ── driver_applications ──────────────────────────────────────
ALTER TABLE driver_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_insert_driver_app" ON driver_applications;
CREATE POLICY "allow_anon_insert_driver_app" ON driver_applications FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "allow_anon_select_driver_app" ON driver_applications;
CREATE POLICY "allow_anon_select_driver_app" ON driver_applications FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_anon_update_driver_app" ON driver_applications;
CREATE POLICY "allow_anon_update_driver_app" ON driver_applications FOR UPDATE USING (true) WITH CHECK (true);


-- ── merchant_applications ────────────────────────────────────
ALTER TABLE merchant_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_insert_merchant_app" ON merchant_applications;
CREATE POLICY "allow_anon_insert_merchant_app" ON merchant_applications FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "allow_anon_select_merchant_app" ON merchant_applications;
CREATE POLICY "allow_anon_select_merchant_app" ON merchant_applications FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_anon_update_merchant_app" ON merchant_applications;
CREATE POLICY "allow_anon_update_merchant_app" ON merchant_applications FOR UPDATE USING (true) WITH CHECK (true);


-- ── orders ───────────────────────────────────────────────────
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_orders" ON orders;
CREATE POLICY "allow_anon_all_orders" ON orders FOR ALL USING (true) WITH CHECK (true);


-- ── rides ────────────────────────────────────────────────────
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_rides" ON rides;
CREATE POLICY "allow_anon_all_rides" ON rides FOR ALL USING (true) WITH CHECK (true);


-- ── driver_locations ─────────────────────────────────────────
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_driver_locations" ON driver_locations;
CREATE POLICY "allow_anon_all_driver_locations" ON driver_locations FOR ALL USING (true) WITH CHECK (true);


-- ── messages ─────────────────────────────────────────────────
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_insert_messages" ON messages;
CREATE POLICY "allow_anon_insert_messages" ON messages FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "allow_anon_select_messages" ON messages;
CREATE POLICY "allow_anon_select_messages" ON messages FOR SELECT USING (true);

DROP POLICY IF EXISTS "allow_anon_update_messages" ON messages;
CREATE POLICY "allow_anon_update_messages" ON messages FOR UPDATE USING (true) WITH CHECK (true);


-- ── stores ───────────────────────────────────────────────────
ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_stores" ON stores;
CREATE POLICY "allow_anon_all_stores" ON stores FOR ALL USING (true) WITH CHECK (true);


-- ── wallets ──────────────────────────────────────────────────
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_wallets" ON wallets;
CREATE POLICY "allow_anon_all_wallets" ON wallets FOR ALL USING (true) WITH CHECK (true);


-- ── push_subscriptions ───────────────────────────────────────
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_push_subs" ON push_subscriptions;
CREATE POLICY "allow_anon_all_push_subs" ON push_subscriptions FOR ALL USING (true) WITH CHECK (true);


-- ── ratings ──────────────────────────────────────────────────
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_anon_all_ratings" ON ratings;
CREATE POLICY "allow_anon_all_ratings" ON ratings FOR ALL USING (true) WITH CHECK (true);
