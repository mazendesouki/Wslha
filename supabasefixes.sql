-- ══════════════════════════════════════════════════════════════
-- وصّلها — Supabase Fix Script
-- Run this in Supabase → SQL Editor
-- ══════════════════════════════════════════════════════════════

-- ── 1. Add driver_reply column to ratings ─────────────────────
ALTER TABLE ratings ADD COLUMN IF NOT EXISTS driver_reply TEXT;
ALTER TABLE ratings ADD COLUMN IF NOT EXISTS customer_name TEXT;

-- ── 2. Fix wallets RLS (allow full access for anon) ───────────
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_anon_all_wallets"          ON wallets;
DROP POLICY IF EXISTS "allow_anon_select_wallets"       ON wallets;
DROP POLICY IF EXISTS "allow_anon_insert_wallets"       ON wallets;
DROP POLICY IF EXISTS "allow_anon_update_wallets"       ON wallets;
DROP POLICY IF EXISTS "allow_anon_delete_wallets"       ON wallets;
CREATE POLICY "allow_anon_all_wallets" ON wallets
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ── 3. wallet_transactions RLS ────────────────────────────────
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_anon_all_wallet_tx"        ON wallet_transactions;
CREATE POLICY "allow_anon_all_wallet_tx" ON wallet_transactions
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ── 4. points RLS ─────────────────────────────────────────────
ALTER TABLE points ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_anon_all_points"           ON points;
CREATE POLICY "allow_anon_all_points" ON points
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ── 5. point_transactions RLS ─────────────────────────────────
ALTER TABLE point_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_anon_all_point_tx"         ON point_transactions;
CREATE POLICY "allow_anon_all_point_tx" ON point_transactions
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ── 6. app_settings table + RLS ───────────────────────────────
CREATE TABLE IF NOT EXISTS app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_anon_select_app_settings"  ON app_settings;
CREATE POLICY "allow_anon_select_app_settings" ON app_settings
  FOR SELECT TO anon, authenticated USING (true);

-- Default commission rates
INSERT INTO app_settings (key, value) VALUES
  ('commission_ride',     '0.15'),
  ('commission_delivery', '0.15'),
  ('commission_airport',  '0.12')
ON CONFLICT (key) DO NOTHING;

-- ── 7. ratings RLS (ensure it's correct) ─────────────────────
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_anon_all_ratings"          ON ratings;
CREATE POLICY "allow_anon_all_ratings" ON ratings
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ── 8. Wallet accumulate function (adds to existing balance) ──
CREATE OR REPLACE FUNCTION add_wallet_balance(p_phone TEXT, p_amount DECIMAL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO wallets (phone, balance, updated_at)
    VALUES (p_phone, p_amount, NOW())
  ON CONFLICT (phone) DO UPDATE
    SET balance    = wallets.balance + EXCLUDED.balance,
        updated_at = NOW();
END;
$$;
