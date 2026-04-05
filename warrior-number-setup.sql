-- ============================================================
-- VibeWars: Warrior Number System
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- 1. Create the warriors table
CREATE TABLE IF NOT EXISTS warriors (
    id SERIAL PRIMARY KEY,
    anonymous_id TEXT UNIQUE NOT NULL,
    warrior_number SERIAL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Enable RLS on warriors
ALTER TABLE warriors ENABLE ROW LEVEL SECURITY;

-- Allow anyone to read warriors
CREATE POLICY "warriors_select" ON warriors
    FOR SELECT USING (true);

-- Allow anyone to insert (the app inserts via service-level RPC, but just in case)
CREATE POLICY "warriors_insert" ON warriors
    FOR INSERT WITH CHECK (true);

-- 3. Add warrior_number column to score_entries so the leaderboard can read it directly
ALTER TABLE score_entries ADD COLUMN IF NOT EXISTS warrior_number INT;

-- 4. Replace the submit_and_rank function to handle warrior numbers
CREATE OR REPLACE FUNCTION submit_and_rank(
    p_anonymous_id TEXT,
    p_vibe_score DOUBLE PRECISION,
    p_period_type TEXT,
    p_period_key TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_warrior_number INT;
    v_rank INT;
    v_total INT;
    v_percentile DOUBLE PRECISION;
BEGIN
    -- Look up or create warrior number
    SELECT warrior_number INTO v_warrior_number
    FROM warriors
    WHERE anonymous_id = p_anonymous_id;

    IF v_warrior_number IS NULL THEN
        INSERT INTO warriors (anonymous_id)
        VALUES (p_anonymous_id)
        ON CONFLICT (anonymous_id) DO NOTHING
        RETURNING warrior_number INTO v_warrior_number;

        -- Handle race condition: if ON CONFLICT fired, re-select
        IF v_warrior_number IS NULL THEN
            SELECT warrior_number INTO v_warrior_number
            FROM warriors
            WHERE anonymous_id = p_anonymous_id;
        END IF;
    END IF;

    -- Upsert the score entry (one row per user per period)
    INSERT INTO score_entries (anonymous_id, vibe_score, period_type, period_key, warrior_number, updated_at)
    VALUES (p_anonymous_id, p_vibe_score, p_period_type, p_period_key, v_warrior_number, now())
    ON CONFLICT (anonymous_id, period_type, period_key)
    DO UPDATE SET vibe_score = EXCLUDED.vibe_score,
                  warrior_number = v_warrior_number,
                  updated_at = now();

    -- Calculate rank
    SELECT COUNT(*) + 1 INTO v_rank
    FROM score_entries
    WHERE period_type = p_period_type
      AND period_key = p_period_key
      AND vibe_score > p_vibe_score;

    SELECT COUNT(*) INTO v_total
    FROM score_entries
    WHERE period_type = p_period_type
      AND period_key = p_period_key;

    -- Percentile: what % of people you're outscoring
    IF v_total <= 1 THEN
        v_percentile := 100.0;
    ELSE
        v_percentile := ROUND(((v_total - v_rank)::DOUBLE PRECISION / (v_total - 1)::DOUBLE PRECISION) * 100, 1);
    END IF;

    RETURN json_build_object(
        'rank', v_rank,
        'total', v_total,
        'percentile', v_percentile,
        'warrior_number', v_warrior_number
    );
END;
$$;
