-- Reliable profile read for the signed-in teacher (used by omr_web).
-- Run once in Supabase → SQL Editor. Safe to re-run.

create or replace function public.get_my_teacher_profile()
returns table (
  id uuid,
  full_name text,
  role text,
  is_active boolean,
  school_name text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    tp.id,
    tp.full_name,
    tp.role,
    tp.is_active,
    tp.school_name,
    tp.created_at,
    tp.updated_at
  from public.teacher_profiles tp
  where tp.id = auth.uid();
$$;

revoke all on function public.get_my_teacher_profile() from public;
grant execute on function public.get_my_teacher_profile() to authenticated;
