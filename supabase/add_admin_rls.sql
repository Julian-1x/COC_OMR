-- School admin RLS for COC OMR web portal (Phase 2 admin dashboard).
-- Run once in Supabase → SQL Editor after schema.sql.
-- Grants read-only cross-teacher visibility within the same school_name.

create or replace function public.is_school_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.teacher_profiles
    where id = auth.uid()
      and role in ('admin', 'school_admin')
      and is_active = true
  );
$$;

create or replace function public.current_user_school()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select school_name from public.teacher_profiles where id = auth.uid();
$$;

create or replace function public.teacher_in_my_school(teacher_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.teacher_profiles tp
    where tp.id = teacher_id
      and tp.school_name is not null
      and tp.school_name = public.current_user_school()
  );
$$;

-- Admins can read teacher profiles in their school (not other schools).
drop policy if exists "School admins read school teachers" on public.teacher_profiles;
create policy "School admins read school teachers"
on public.teacher_profiles
for select
to authenticated
using (
  public.is_school_admin()
  and school_name is not null
  and school_name = public.current_user_school()
);

-- Read-only admin visibility into exam data for teachers in the same school.
drop policy if exists "School admins read school sections" on public.sections;
create policy "School admins read school sections"
on public.sections
for select
to authenticated
using (public.is_school_admin() and public.teacher_in_my_school(owner_teacher_id));

drop policy if exists "School admins read school students" on public.students;
create policy "School admins read school students"
on public.students
for select
to authenticated
using (public.is_school_admin() and public.teacher_in_my_school(owner_teacher_id));

drop policy if exists "School admins read school subjects" on public.subjects;
create policy "School admins read school subjects"
on public.subjects
for select
to authenticated
using (public.is_school_admin() and public.teacher_in_my_school(owner_teacher_id));

drop policy if exists "School admins read school scan results" on public.scan_results;
create policy "School admins read school scan results"
on public.scan_results
for select
to authenticated
using (public.is_school_admin() and public.teacher_in_my_school(owner_teacher_id));

drop policy if exists "School admins read school deadlines" on public.deadlines;
create policy "School admins read school deadlines"
on public.deadlines
for select
to authenticated
using (public.is_school_admin() and public.teacher_in_my_school(owner_teacher_id));

-- Promote a user to school admin (run manually for IT lead):
-- update public.teacher_profiles set role = 'school_admin' where id = 'USER-UUID-HERE';
