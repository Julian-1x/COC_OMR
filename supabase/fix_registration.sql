-- Run this in Supabase SQL Editor if Register says "policy" or "row-level security".
-- Safe to run more than once.

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
on public.teacher_profiles for select to authenticated
using (auth.uid() = id);

create policy "Teachers can create own profile"
on public.teacher_profiles for insert to authenticated
with check (auth.uid() = id);

create policy "Teachers can update own profile"
on public.teacher_profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

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

-- Backfill profiles for accounts that registered before this fix
insert into public.teacher_profiles (id, full_name, school_name, role, is_active)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
  nullif(u.raw_user_meta_data->>'school', ''),
  coalesce(u.raw_user_meta_data->>'role', 'teacher'),
  true
from auth.users u
where not exists (
  select 1 from public.teacher_profiles p where p.id = u.id
);
