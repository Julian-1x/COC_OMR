-- Run once on production BEFORE deploying app/web that upsert on school_id.
-- Removes duplicate students (same owner + school_id), keeps lowest omr_id
-- (or any row that already has scan_results).

-- 1) Re-point scan_results from duplicate OMR rows to the keeper OMR.
with ranked as (
  select
    id,
    owner_teacher_id,
    school_id,
    omr_id,
    row_number() over (
      partition by owner_teacher_id, upper(trim(school_id))
      order by
        case
          when exists (
            select 1
            from public.scan_results sr
            where sr.owner_teacher_id = students.owner_teacher_id
              and sr.student_omr_id = students.omr_id
          ) then 0
          else 1
        end,
        omr_id asc
    ) as rn
  from public.students
),
keepers as (
  select owner_teacher_id, upper(trim(school_id)) as school_key, omr_id as keep_omr
  from ranked
  where rn = 1
),
losers as (
  select s.owner_teacher_id, s.omr_id as loser_omr, k.keep_omr
  from public.students s
  join keepers k
    on k.owner_teacher_id = s.owner_teacher_id
   and k.school_key = upper(trim(s.school_id))
  where s.omr_id <> k.keep_omr
)
update public.scan_results sr
set
  student_omr_id = l.keep_omr,
  updated_at = now()
from losers l
where sr.owner_teacher_id = l.owner_teacher_id
  and sr.student_omr_id = l.loser_omr;

-- 2) Delete duplicate student rows.
with ranked as (
  select
    id,
    owner_teacher_id,
    school_id,
    omr_id,
    row_number() over (
      partition by owner_teacher_id, upper(trim(school_id))
      order by
        case
          when exists (
            select 1
            from public.scan_results sr
            where sr.owner_teacher_id = students.owner_teacher_id
              and sr.student_omr_id = students.omr_id
          ) then 0
          else 1
        end,
        omr_id asc
    ) as rn
  from public.students
)
delete from public.students s
using ranked r
where s.id = r.id
  and r.rn > 1;

-- 3) Enforce one row per teacher + school ID.
create unique index if not exists students_owner_school_id_unique
  on public.students (owner_teacher_id, school_id);
