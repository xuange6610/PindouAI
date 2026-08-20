CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug varchar(40) UNIQUE NOT NULL,
  name varchar(120) NOT NULL,
  bead_size_mm numeric(4,1) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS palettes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id uuid NOT NULL REFERENCES brands(id),
  name varchar(120) NOT NULL,
  version varchar(40) NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'draft',
  source varchar(200),
  measured_illuminant varchar(20),
  measured_observer varchar(20),
  published_at timestamptz,
  UNIQUE (brand_id, version)
);

CREATE TABLE IF NOT EXISTS colors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  palette_id uuid NOT NULL REFERENCES palettes(id),
  series varchar(8) NOT NULL,
  code varchar(16) NOT NULL,
  color_name_cn varchar(80) NOT NULL,
  color_name_en varchar(80) NOT NULL,
  red smallint NOT NULL CHECK (red BETWEEN 0 AND 255),
  green smallint NOT NULL CHECK (green BETWEEN 0 AND 255),
  blue smallint NOT NULL CHECK (blue BETWEEN 0 AND 255),
  hex char(7) NOT NULL,
  lab_l numeric(7,3) NOT NULL,
  lab_a numeric(7,3) NOT NULL,
  lab_b numeric(7,3) NOT NULL,
  size_mm numeric(4,1) NOT NULL,
  color_type varchar(24) NOT NULL DEFAULT 'solid',
  is_measured boolean NOT NULL DEFAULT false,
  sort_order smallint NOT NULL,
  UNIQUE (palette_id, code)
);

CREATE INDEX IF NOT EXISTS colors_palette_series_idx
  ON colors (palette_id, series, sort_order);
CREATE INDEX IF NOT EXISTS colors_lab_idx
  ON colors (palette_id, lab_l, lab_a, lab_b);

CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  palette_id uuid NOT NULL REFERENCES palettes(id),
  title varchar(160) NOT NULL,
  width smallint NOT NULL CHECK (width BETWEEN 1 AND 500),
  height smallint NOT NULL CHECK (height BETWEEN 1 AND 500),
  source_object_key varchar(500),
  result_object_key varchar(500),
  status varchar(24) NOT NULL DEFAULT 'queued',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO brands (slug, name, bead_size_mm)
VALUES ('mard', 'MARD', 2.6)
ON CONFLICT (slug) DO NOTHING;
