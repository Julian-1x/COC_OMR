-- Sync offline PIN hash across devices (run once in Supabase SQL Editor).
-- Stores salted SHA-256 hash only — never the raw PIN digits.

alter table public.teacher_profiles
  add column if not exists pin_hash text,
  add column if not exists pin_salt text;
