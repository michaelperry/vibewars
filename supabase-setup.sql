-- VibeCheck Supabase Schema
-- Run this in the Supabase SQL Editor after creating your project

-- Score entries table
CREATE TABLE score_entries (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    anonymous_id TEXT NOT NULL,          -- SHA256 hash, not reversible to any identity
    vibe_score DOUBLE PRECISION NOT NULL CHECK (vibe_score >= 0 AND vibe_score <= 100),
    period_type TEXT NOT NULL CHECK (period_type IN ('daily', 'weekly')),
    period_key TEXT NOT NULL,            -- "2026-04-05" or "2026-W14"
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    -- One score per user per period
    UNIQUE (anonymous_id, period_type, period_key)
);

-- Indexes for fast ranking queries
CREATE INDEX idx_score_period ON score_entries (period_type, period_key, vibe_score DESC);
CREATE INDEX idx_score_lookup ON score_entries (anonymous_id, period_type, period_key);

-- Enable Row Level Security
ALTER TABLE score_entries ENABLE ROW LEVEL SECURITY;

-- Anyone can read scores (needed for ranking counts)
CREATE POLICY "Scores are publicly readable"
    ON score_entries FOR SELECT
    USING (true);

-- Anyone can insert their own score (anonymous, no auth required)
CREATE POLICY "Anyone can insert scores"
    ON score_entries FOR INSERT
    WITH CHECK (true);

-- Users can only update their own scores (matched by anonymous_id)
CREATE POLICY "Users can update own scores"
    ON score_entries FOR UPDATE
    USING (true)
    WITH CHECK (true);

-- Server-side function for atomic upsert + rank retrieval
-- Returns rank, total, and percentile in a single round trip
CREATE OR REPLACE FUNCTION submit_and_rank(
    p_anonymous_id TEXT,
    p_vibe_score DOUBLE PRECISION,
    p_period_type TEXT,
    p_period_key TEXT
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_rank INT;
    v_total INT;
    v_percentile DOUBLE PRECISION;
BEGIN
    -- Upsert the score
    INSERT INTO score_entries (anonymous_id, vibe_score, period_type, period_key, updated_at)
    VALUES (p_anonymous_id, p_vibe_score, p_period_type, p_period_key, now())
    ON CONFLICT (anonymous_id, period_type, period_key)
    DO UPDATE SET vibe_score = p_vibe_score, updated_at = now();

    -- Count users with higher scores (rank)
    SELECT COUNT(*) + 1 INTO v_rank
    FROM score_entries
    WHERE period_type = p_period_type
      AND period_key = p_period_key
      AND vibe_score > p_vibe_score;

    -- Count total users for this period
    SELECT COUNT(*) INTO v_total
    FROM score_entries
    WHERE period_type = p_period_type
      AND period_key = p_period_key;

    -- Calculate percentile
    IF v_total > 1 THEN
        v_percentile := (v_total - v_rank)::DOUBLE PRECISION / (v_total - 1) * 100.0;
    ELSE
        v_percentile := 100.0;
    END IF;

    RETURN json_build_object(
        'rank', v_rank,
        'total', v_total,
        'percentile', v_percentile
    );
END;
$$;
