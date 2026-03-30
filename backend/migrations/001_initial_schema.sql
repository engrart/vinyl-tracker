-- VinylTracker — initial schema
-- Run: psql $DATABASE_URL -f migrations/001_initial_schema.sql

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Users ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  clerk_user_id  TEXT        NOT NULL UNIQUE,
  email          TEXT        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_clerk_user_id ON users (clerk_user_id);

-- ─── Records ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS records (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  artist      TEXT        NOT NULL,
  year        INTEGER     CHECK (year IS NULL OR (year >= 1900 AND year <= 2100)),
  genre       TEXT,
  notes       TEXT,
  condition   TEXT        CHECK (condition IS NULL OR condition IN ('M','NM','VG+','VG','G+','G','F','P')),
  date_added  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  mbid        TEXT,                    -- MusicBrainz release ID
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_records_user_id  ON records (user_id);
CREATE INDEX IF NOT EXISTS idx_records_artist   ON records (user_id, artist);
CREATE INDEX IF NOT EXISTS idx_records_title    ON records (user_id, title);
CREATE INDEX IF NOT EXISTS idx_records_genre    ON records (user_id, genre);
CREATE INDEX IF NOT EXISTS idx_records_year     ON records (user_id, year);
CREATE INDEX IF NOT EXISTS idx_records_mbid     ON records (mbid) WHERE mbid IS NOT NULL;

-- full-text search vector (artist + title)
ALTER TABLE records ADD COLUMN IF NOT EXISTS fts tsvector
  GENERATED ALWAYS AS (to_tsvector('english', coalesce(artist,'') || ' ' || coalesce(title,''))) STORED;

CREATE INDEX IF NOT EXISTS idx_records_fts ON records USING GIN (fts);

-- ─── Record Images ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS record_images (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  record_id   UUID        NOT NULL REFERENCES records (id) ON DELETE CASCADE,
  image_url   TEXT        NOT NULL,
  image_type  TEXT        NOT NULL CHECK (image_type IN ('cover','label','photo')),
  is_primary  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_record_images_record_id ON record_images (record_id);
-- partial index: fast lookup of single primary image per record
CREATE UNIQUE INDEX IF NOT EXISTS idx_record_images_primary
  ON record_images (record_id)
  WHERE is_primary = TRUE;

-- ─── updated_at trigger ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS records_set_updated_at ON records;
CREATE TRIGGER records_set_updated_at
  BEFORE UPDATE ON records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
