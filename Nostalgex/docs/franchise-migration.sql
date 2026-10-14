-- Phase 0: Franchise membership columns
-- Run once in the Supabase SQL editor against the current `media_enrichments`
-- table. Both columns are nullable so older rows created before this migration
-- (and any cached rows the app already holds) keep decoding without a backfill.
--
-- franchise_id   = TMDB `belongs_to_collection.id`   (movies only; TV has none)
-- franchise_name = TMDB `belongs_to_collection.name` (movies only; TV has none)
--
-- Populated on the next enrichment fetch; a backfill over existing tmdb_ids can
-- fill historical rows later.

alter table media_enrichments add column if not exists franchise_id integer;
alter table media_enrichments add column if not exists franchise_name text;

-- Index for grouping a library's films by franchise.
create index if not exists media_enrichments_franchise_id_idx on media_enrichments(franchise_id);

-- Verify
-- select column_name, data_type from information_schema.columns where table_name = 'media_enrichments';
