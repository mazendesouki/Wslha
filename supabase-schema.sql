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
