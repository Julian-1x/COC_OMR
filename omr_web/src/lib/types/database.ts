export type DbSection = {
  id: string;
  owner_teacher_id: string;
  name: string;
  teacher: string | null;
  student_count: number | null;
  school_year: string | null;
  term_label: string | null;
  archived_at: string | null;
  local_id: string | null;
  sync_status: string;
  created_at: string;
  updated_at: string;
};

export type DbStudent = {
  id: string;
  owner_teacher_id: string;
  school_id: string;
  omr_id: string;
  name: string;
  section_name: string;
  score: number | null;
  answers: Record<string, string> | null;
  scan_date: string | null;
  confidence: number | null;
  local_id: string | null;
  sync_status: string;
  created_at: string;
  updated_at: string;
};

export type DbSubject = {
  id: string;
  owner_teacher_id: string;
  local_id: string;
  name: string;
  answer_key: Record<string, string | string[]>;
  total_questions: number;
  section_names: string[] | null;
  section_qr_data: Record<string, string>;
  exam_date: string | null;
  passing_score: number;
  use_partial_credit: boolean;
  sync_status: string;
  created_at: string;
  updated_at: string;
};

export type DbScanResult = {
  id: string;
  owner_teacher_id: string;
  student_omr_id: string;
  subject_id: string | null;
  subject_local_id: string | null;
  subject_name: string;
  sheet_id: string | null;
  detected_answers: Record<string, string>;
  correctness_map: Record<string, boolean | number>;
  score: number;
  total_questions: number;
  confidence: number | null;
  scan_time: string;
  review_reasons: string[] | null;
  flagged_questions: number[] | null;
  manually_confirmed: boolean;
  needs_review: boolean;
  local_id: string | null;
  sync_status: string;
  created_at: string;
  updated_at: string;
};

export type DbTeacherProfile = {
  id: string;
  full_name: string;
  role: string;
  is_active: boolean;
  school_name: string | null;
  created_at: string;
  updated_at: string;
};

export type AnswerKeyMap = Record<string, string | string[]>;
