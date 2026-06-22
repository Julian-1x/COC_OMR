-- Run once in Supabase SQL Editor after schema.sql (section archival + school year).
-- Safe to re-run.

alter table public.sections
  add column if not exists school_year text,
  add column if not exists term_label text,
  add column if not exists archived_at timestamptz;

create index if not exists idx_sections_owner_archived
  on public.sections(owner_teacher_id, archived_at);

create index if not exists idx_sections_owner_school_year
  on public.sections(owner_teacher_id, school_year);

comment on column public.sections.archived_at is
  'When set, section is archived in cloud. Phone sync does not re-download archived sections.';
