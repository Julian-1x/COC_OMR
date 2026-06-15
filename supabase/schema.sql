-- COC OMR — full Supabase schema.
-- Run this entire file once in Supabase → SQL Editor → New query → Run.

create table if not exists public.teacher_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'teacher',
  is_active boolean not null default true,
  school_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.teacher_profiles enable row level security;

drop policy if exists "Teachers can read own profile" on public.teacher_profiles;
drop policy if exists "Teachers can create own profile" on public.teacher_profiles;
drop policy if exists "Teachers can update own profile" on public.teacher_profiles;

create policy "Teachers can read own profile"
on public.teacher_profiles
for select
to authenticated
using (auth.uid() = id);

create policy "Teachers can create own profile"
on public.teacher_profiles
for insert
to authenticated
with check (auth.uid() = id);

create policy "Teachers can update own profile"
on public.teacher_profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- Create teacher_profiles automatically when auth.users row is inserted.
-- Fixes "no policy" errors during Register when the session is not ready yet.
create or replace function public.handle_new_teacher_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.teacher_profiles (
    id,
    full_name,
    school_name,
    role,
    is_active
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    nullif(new.raw_user_meta_data->>'school', ''),
    coalesce(new.raw_user_meta_data->>'role', 'teacher'),
    true
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    school_name = coalesce(excluded.school_name, teacher_profiles.school_name),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_teacher on auth.users;
create trigger on_auth_user_created_teacher
  after insert on auth.users
  for each row execute function public.handle_new_teacher_user();

create table if not exists public.sections (
  id uuid primary key default gen_random_uuid(),
  owner_teacher_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  teacher text,
  student_count integer,
  local_id text,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_teacher_id, name)
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  owner_teacher_id uuid not null references auth.users(id) on delete cascade,
  school_id text not null,
  omr_id text not null,
  name text not null,
  section_name text not null,
  score numeric,
  answers jsonb,
  scan_date timestamptz,
  confidence numeric,
  local_id text,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_teacher_id, omr_id)
);

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  owner_teacher_id uuid not null references auth.users(id) on delete cascade,
  local_id text not null,
  name text not null,
  answer_key jsonb not null,
  total_questions integer not null,
  section_names jsonb,
  section_qr_data jsonb not null default '{}'::jsonb,
  exam_date date,
  passing_score integer not null,
  use_partial_credit boolean not null default false,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_teacher_id, local_id)
);

create table if not exists public.scan_results (
  id uuid primary key default gen_random_uuid(),
  owner_teacher_id uuid not null references auth.users(id) on delete cascade,
  student_omr_id text not null,
  subject_id uuid references public.subjects(id) on delete set null,
  subject_local_id text,
  subject_name text not null,
  sheet_id text,
  detected_answers jsonb not null,
  correctness_map jsonb not null,
  score numeric not null,
  total_questions integer not null,
  confidence numeric not null,
  scan_time timestamptz not null,
  scanned_image_path text,
  review_reasons jsonb,
  flagged_questions jsonb,
  manually_confirmed boolean not null default false,
  needs_review boolean not null default false,
  local_id text,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_teacher_id, student_omr_id, subject_local_id, scan_time)
);

create table if not exists public.deadlines (
  id uuid primary key default gen_random_uuid(),
  owner_teacher_id uuid not null references auth.users(id) on delete cascade,
  local_id text not null,
  title text not null,
  section_name text,
  subject_id uuid references public.subjects(id) on delete cascade,
  subject_local_id text,
  due_date timestamptz not null,
  is_completed boolean not null default false,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_teacher_id, local_id)
);

create table if not exists public.scan_warnings (
  id uuid primary key default gen_random_uuid(),
  owner_teacher_id uuid not null references auth.users(id) on delete cascade,
  scan_result_id uuid references public.scan_results(id) on delete cascade,
  question_number integer,
  reason text not null,
  metadata jsonb,
  created_at timestamptz not null default now()
);

alter table public.sections enable row level security;
alter table public.students enable row level security;
alter table public.subjects enable row level security;
alter table public.scan_results enable row level security;
alter table public.deadlines enable row level security;
alter table public.scan_warnings enable row level security;

drop policy if exists "Teachers manage own sections" on public.sections;
drop policy if exists "Teachers manage own students" on public.students;
drop policy if exists "Teachers manage own subjects" on public.subjects;
drop policy if exists "Teachers manage own scan results" on public.scan_results;
drop policy if exists "Teachers manage own deadlines" on public.deadlines;
drop policy if exists "Teachers manage own scan warnings" on public.scan_warnings;

create policy "Teachers manage own sections"
on public.sections for all to authenticated
using (auth.uid() = owner_teacher_id)
with check (auth.uid() = owner_teacher_id);

create policy "Teachers manage own students"
on public.students for all to authenticated
using (auth.uid() = owner_teacher_id)
with check (auth.uid() = owner_teacher_id);

create policy "Teachers manage own subjects"
on public.subjects for all to authenticated
using (auth.uid() = owner_teacher_id)
with check (auth.uid() = owner_teacher_id);

create policy "Teachers manage own scan results"
on public.scan_results for all to authenticated
using (auth.uid() = owner_teacher_id)
with check (auth.uid() = owner_teacher_id);

create policy "Teachers manage own deadlines"
on public.deadlines for all to authenticated
using (auth.uid() = owner_teacher_id)
with check (auth.uid() = owner_teacher_id);

create policy "Teachers manage own scan warnings"
on public.scan_warnings for all to authenticated
using (auth.uid() = owner_teacher_id)
with check (auth.uid() = owner_teacher_id);

create index if not exists idx_students_owner_section
on public.students(owner_teacher_id, section_name);

create index if not exists idx_subjects_owner_name
on public.subjects(owner_teacher_id, name);

create index if not exists idx_scan_results_owner_student
on public.scan_results(owner_teacher_id, student_omr_id);

create index if not exists idx_scan_results_owner_subject
on public.scan_results(owner_teacher_id, subject_local_id);

create unique index if not exists idx_scan_results_owner_local_id
on public.scan_results(owner_teacher_id, local_id)
where local_id is not null;

create index if not exists idx_deadlines_owner_due_date
on public.deadlines(owner_teacher_id, due_date);
