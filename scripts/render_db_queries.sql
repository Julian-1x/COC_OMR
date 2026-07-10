-- COC OMR — useful queries for Render PostgreSQL (coc_omr)
-- Run in DBeaver after connecting to your Render database.

-- All teacher accounts
SELECT
  u.id,
  u.email,
  u.email_verified_at,
  u.created_at,
  tp.full_name,
  tp.school_name,
  tp.role,
  tp.is_active
FROM users u
LEFT JOIN teacher_profiles tp ON tp.id = u.id
ORDER BY u.created_at DESC;

-- Table row counts (quick health check)
SELECT 'users' AS table_name, COUNT(*) AS rows FROM users
UNION ALL SELECT 'teacher_profiles', COUNT(*) FROM teacher_profiles
UNION ALL SELECT 'sections', COUNT(*) FROM sections
UNION ALL SELECT 'students', COUNT(*) FROM students
UNION ALL SELECT 'subjects', COUNT(*) FROM subjects
UNION ALL SELECT 'scan_results', COUNT(*) FROM scan_results;
