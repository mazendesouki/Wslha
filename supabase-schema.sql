-- ── Driver Live Locations ────────────────────────────────────
CREATE TABLE IF NOT EXISTS driver_locations (
  driver_phone  TEXT PRIMARY KEY,
  driver_name   TEXT,
  lat           DOUBLE PRECISION NOT NULL,
  lng           DOUBLE PRECISION NOT NULL,
  heading       DOUBLE PRECISION DEFAULT 0,
  is_online     BOOLEAN DEFAULT false,
  ride_id       TEXT,
  updated_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_driver_locations_online ON driver_locations(is_online);
CREATE INDEX idx_driver_locations_updated ON driver_locations(updated_at DESC);


-- ── Contact Messages ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  phone      TEXT NOT NULL,
  email      TEXT,
  subject    TEXT NOT NULL,
  message    TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'unread', -- unread, read, replied
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_messages_status     ON messages(status);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);


-- ── Driver Applications ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS driver_applications (
  id TEXT PRIMARY KEY,
  phone TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, approved, rejected

  -- Personal Info
  full_name TEXT NOT NULL,
  national_id_number TEXT NOT NULL,
  national_id_expiry DATE NOT NULL,
  national_id_front_url TEXT,
  national_id_back_url TEXT,

  -- License
  license_number TEXT NOT NULL,
  license_expiry DATE NOT NULL,
  license_photo_url TEXT,

  -- Vehicle Registration
  vehicle_reg_number TEXT NOT NULL,
  vehicle_reg_expiry DATE NOT NULL,
  vehicle_reg_photo_url TEXT,

  -- Insurance & Inspection
  insurance_expiry DATE NOT NULL,
  insurance_photo_url TEXT,
  inspection_expiry DATE NOT NULL,
  inspection_photo_url TEXT,

  -- Vehicle Info
  vehicle_model TEXT NOT NULL,
  vehicle_color TEXT NOT NULL,
  vehicle_year TEXT NOT NULL,
  vehicle_purchase_date DATE,
  vehicle_ownership TEXT NOT NULL DEFAULT 'owned', -- owned, financed, leased

  -- Vehicle Photos
  vehicle_front_url TEXT,
  vehicle_back_url TEXT,
  vehicle_right_url TEXT,
  vehicle_left_url TEXT,

  -- Verification
  plate_photo_url TEXT,
  handwritten_text TEXT NOT NULL,
  handwritten_photo_url TEXT,

  -- Driver Photo
  driver_photo_url TEXT,

  -- Additional
  good_conduct_url TEXT,
  uses_drugs TEXT NOT NULL DEFAULT 'no', -- yes, no

  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  FOREIGN KEY (phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE INDEX idx_driver_applications_phone ON driver_applications(phone);
CREATE INDEX idx_driver_applications_status ON driver_applications(status);


-- ── Merchant Applications ────────────────────────────────────
CREATE TABLE IF NOT EXISTS merchant_applications (
  id TEXT PRIMARY KEY,
  phone TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, approved, rejected

  -- Business Info
  business_name TEXT NOT NULL,
  business_type TEXT NOT NULL,
  business_address TEXT NOT NULL,

  -- Commercial Registration
  commercial_reg_number TEXT NOT NULL,
  commercial_reg_date DATE NOT NULL,
  commercial_reg_url TEXT,

  -- National ID
  national_id_number TEXT NOT NULL,
  national_id_expiry DATE,
  national_id_url TEXT,

  -- Tax Card
  tax_card_number TEXT NOT NULL,
  tax_card_url TEXT,

  -- Work Permit
  work_permit_url TEXT,

  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  FOREIGN KEY (phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE INDEX idx_merchant_applications_phone ON merchant_applications(phone);
CREATE INDEX idx_merchant_applications_status ON merchant_applications(status);


-- ── Supabase Storage: Create 'documents' bucket ───────────────
-- Run this via Supabase dashboard or SQL editor:
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('documents', 'documents', true);

-- ── Set storage policy for documents bucket ──────────────────
-- INSERT INTO storage.policies (bucket_id, name, definition)
-- SELECT 'documents', 'Allow authenticated uploads',
--   '{"bucket_id":"documents","definition":{"role":"authenticated"},"action":"INSERT"}'
-- WHERE NOT EXISTS (SELECT 1 FROM storage.policies WHERE bucket_id = 'documents');


-- ── Driver & Merchant Wallets ────────────────────────────────
CREATE TABLE IF NOT EXISTS wallets (
  phone       TEXT PRIMARY KEY,
  balance     DECIMAL(12,2) NOT NULL DEFAULT 0,
  updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id          TEXT PRIMARY KEY,
  phone       TEXT NOT NULL,
  amount      DECIMAL(12,2) NOT NULL,       -- positive=credit, negative=debit
  type        TEXT NOT NULL,                -- commission, earning, topup, withdrawal, refund
  reference_id TEXT,                        -- ride_id / order_id
  note        TEXT,
  created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE INDEX idx_wallet_tx_phone      ON wallet_transactions(phone);
CREATE INDEX idx_wallet_tx_created_at ON wallet_transactions(created_at DESC);


-- ── Points System ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS points (
  phone        TEXT PRIMARY KEY,
  total_points INT NOT NULL DEFAULT 0,
  updated_at   TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS point_transactions (
  id           TEXT PRIMARY KEY,
  phone        TEXT NOT NULL,
  points       INT NOT NULL,               -- positive=earned, negative=redeemed
  type         TEXT NOT NULL,              -- ride, delivery, airport, bonus, redeem
  reference_id TEXT,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE INDEX idx_point_tx_phone      ON point_transactions(phone);
CREATE INDEX idx_point_tx_created_at ON point_transactions(created_at DESC);


-- ── Customer Ratings ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ratings (
  id            TEXT PRIMARY KEY,
  driver_phone  TEXT NOT NULL,
  customer_phone TEXT,
  ride_id       TEXT,
  order_id      TEXT,
  service_type  TEXT NOT NULL DEFAULT 'ride', -- ride, delivery, airport
  rating        SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment       TEXT,
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (driver_phone) REFERENCES accounts(phone) ON DELETE CASCADE
);

CREATE INDEX idx_ratings_driver_phone  ON ratings(driver_phone);
CREATE INDEX idx_ratings_created_at    ON ratings(created_at DESC);