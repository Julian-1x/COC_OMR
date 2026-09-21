-- Run once in Supabase SQL Editor if using Supabase students table directly.
alter table public.students
  add column if not exists archived_at timestamptz;

create index if not exists idx_students_owner_archived
  on public.students(owner_teacher_id, archived_at);

comment on column public.students.archived_at is
  'When set, student is archived (Phone Archive upload). Phone sync snapshot excludes archived students.';
