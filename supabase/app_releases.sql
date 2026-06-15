-- Optional: powers the in-app "update available" banner.
-- Run once in Supabase → SQL Editor. Then insert a row each time you ship a
-- new APK. The app reads the highest build_number and compares it to the
-- running build. If this table is absent, the app simply never nudges.

create table if not exists public.app_releases (
  id bigint generated always as identity primary key,
  build_number integer not null,
  version_name text not null,
  download_url text,
  notes text,
  mandatory boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.app_releases enable row level security;

-- Any signed-in teacher may read the latest release info.
drop policy if exists "Anyone signed in can read releases" on public.app_releases;
create policy "Anyone signed in can read releases"
on public.app_releases
for select
to authenticated
using (true);

-- Example: after building build +2 (version 1.0.1), publish it:
-- insert into public.app_releases (build_number, version_name, download_url, notes)
-- values (2, '1.0.1', 'https://your-link/app-release.apk', 'Calmer UI, auto-sync, exam progress.');
