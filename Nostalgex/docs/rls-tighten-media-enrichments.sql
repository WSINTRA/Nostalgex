-- Tighten RLS on media_enrichments (2026-09-10)
-- Keyword cap raised from 50 to 100 on 2026-10-13: six real TMDB titles carry 52 to 71
-- keywords, and at 50 their rows could not be updated at all (no ratings, no franchise
-- data). Applied in the Supabase SQL editor the same day.
-- Run in Supabase SQL editor.
--
-- Context: rls-migration.sql enabled RLS but left INSERT/UPDATE as
-- `with check (true)` / `using (true)` — fully unrestricted. Since the
-- anon key is public (embedded in the app binary, and this repo is going
-- public too), anyone could insert junk rows or overwrite existing
-- enrichment data with garbage. This replaces those two policies with a
-- shared validity check matching the actual shape of data the app writes
-- (see Nostalgex/Nostalgex/Models/MediaEnrichment.swift). SELECT is left
-- as-is: it's public movie/TV metadata, no reason to restrict reads.

drop policy if exists "anon_insert_media_enrichments" on public.media_enrichments;
drop policy if exists "anon_update_media_enrichments" on public.media_enrichments;

create or replace function public.media_enrichment_is_valid(rec public.media_enrichments)
returns boolean
language sql
immutable
as $$
  select
    rec.tmdb_id ~ '^[0-9]{1,10}$'
    and rec.media_type in ('movie', 'tv')
    and (rec.imdb_id is null or rec.imdb_id ~ '^tt[0-9]{1,10}$')
    and coalesce(array_length(rec.keywords, 1), 0) <= 100
    and coalesce(array_length(rec.networks, 1), 0) <= 50
    and coalesce(array_length(rec.production_companies, 1), 0) <= 50
    and coalesce(array_length(rec.tmdb_genres, 1), 0) <= 50
    and not exists (
      select 1 from unnest(
        coalesce(rec.keywords, '{}')
        || coalesce(rec.networks, '{}')
        || coalesce(rec.production_companies, '{}')
        || coalesce(rec.tmdb_genres, '{}')
      ) as v where length(v) > 200
    )
    and (rec.imdb_rating is null or rec.imdb_rating between 0 and 10)
    and (rec.imdb_votes is null or rec.imdb_votes >= 0)
    and (rec.rt_score is null or rec.rt_score between 0 and 100)
    and (rec.metacritic_score is null or rec.metacritic_score between 0 and 100)
    and (rec.awards is null or length(rec.awards) <= 1000)
$$;

create policy "anon_insert_media_enrichments"
  on public.media_enrichments
  for insert
  to anon
  with check (public.media_enrichment_is_valid(media_enrichments));

create policy "anon_update_media_enrichments"
  on public.media_enrichments
  for update
  to anon
  using (true)
  with check (public.media_enrichment_is_valid(media_enrichments));

-- NOTE: this stops sloppy/automated spam and out-of-range garbage, but does
-- not stop a determined attacker who mimics valid-shaped data to overwrite
-- a specific title with plausible-but-wrong info. Accepted tradeoff for a
-- free hobby app with no PII/payment data — the real fix would be moving
-- writes behind a server-side Edge Function that validates against a live
-- TMDB/OMDb lookup before accepting.

-- Verify:
-- select polname, cmd, roles, qual, with_check from pg_policies where tablename = 'media_enrichments';
