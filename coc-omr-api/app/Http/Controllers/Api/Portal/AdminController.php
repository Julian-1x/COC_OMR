<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Services\TeacherScopeService;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdminController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
    ) {}

    public function stats(Request $request): JsonResponse
    {
        $summaries = $this->teacherSummaries($request);

        return response()->json([
            'teacher_count' => count($summaries),
            'section_count' => array_sum(array_column($summaries, 'section_count')),
            'student_count' => array_sum(array_column($summaries, 'student_count')),
            'subject_count' => array_sum(array_column($summaries, 'subject_count')),
            'scan_count' => array_sum(array_column($summaries, 'scan_count')),
            'pending_review' => array_sum(array_column($summaries, 'pending_review_count')),
            'teachers_with_no_scans' => count(array_filter(
                $summaries,
                fn (array $row) => $row['scan_count'] === 0,
            )),
        ]);
    }

    public function teachers(Request $request): JsonResponse
    {
        return response()->json([
            'teachers' => $this->teacherSummaries($request),
        ]);
    }

    public function teacher(Request $request, string $teacherId): JsonResponse
    {
        $admin = $request->user();
        $teacher = $this->scopedTeacherProfile($admin, $teacherId);

        if ($teacher === null) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        $sectionRows = $this->scope->schoolWideSectionsQuery($admin)
            ->where('owner_teacher_id', $teacherId)
            ->orderBy('name')
            ->get(['name']);

        $studentRows = $this->scope->schoolWideStudentsQuery($admin)
            ->where('owner_teacher_id', $teacherId)
            ->get(['section_name']);

        $countsBySection = [];
        foreach ($studentRows as $row) {
            $section = (string) $row->section_name;
            if ($section === '') {
                continue;
            }
            $countsBySection[$section] = ($countsBySection[$section] ?? 0) + 1;
        }

        $sections = $sectionRows->map(fn ($row) => [
            'name' => $row->name,
            'student_count' => $countsBySection[$row->name] ?? 0,
        ])->values();

        return response()->json([
            'teacher' => $teacher,
            'section_count' => $this->scope->schoolWideSectionsQuery($admin)->where('owner_teacher_id', $teacherId)->count(),
            'student_count' => $this->scope->schoolWideStudentsQuery($admin)->where('owner_teacher_id', $teacherId)->count(),
            'subject_count' => $this->scope->schoolWideSubjectsQuery($admin)->where('owner_teacher_id', $teacherId)->count(),
            'scan_count' => $this->scope->schoolWideScanResultsQuery($admin)->where('owner_teacher_id', $teacherId)->count(),
            'pending_review_count' => $this->scope->schoolWideScanResultsQuery($admin)
                ->where('owner_teacher_id', $teacherId)
                ->where('needs_review', true)
                ->count(),
            'last_cloud_update' => $this->latestUpdateForTeacher($admin, $teacherId),
            'sections' => $sections,
        ]);
    }

    public function sectionStudents(Request $request, string $teacherId, string $sectionName): JsonResponse
    {
        $admin = $request->user();
        $teacher = $this->scopedTeacherProfile($admin, $teacherId);

        if ($teacher === null) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        $students = $this->scope->schoolWideStudentsQuery($admin)
            ->where('owner_teacher_id', $teacherId)
            ->where('section_name', $sectionName)
            ->orderBy('name')
            ->get();

        return response()->json(['students' => $students]);
    }

    public function accessRequests(Request $request): JsonResponse
    {
        $admin = $request->user();
        $teachers = $this->scope->schoolTeachersQuery($admin)
            ->with('user')
            ->where('access_status', CocSchool::ACCESS_PENDING)
            ->whereHas('user', function ($query) {
                $query->whereNotNull('email_verified_at');
            })
            ->orderBy('created_at')
            ->get();

        return response()->json([
            'teachers' => $teachers->map(fn (TeacherProfile $teacher) => [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'role' => $teacher->role,
                'access_status' => $teacher->access_status,
                'school_name' => $teacher->school_name,
                'department' => $teacher->department,
                'created_at' => $teacher->created_at?->toIso8601String(),
            ])->values()->all(),
        ]);
    }

    public function approve(Request $request, string $teacherId): JsonResponse
    {
        $admin = $request->user();
        $teacher = $this->scopedTeacherProfile($admin, $teacherId);

        if ($teacher === null) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        if ($teacher->id === $admin->id) {
            return response()->json(['message' => 'You cannot change your own access status here.'], 422);
        }

        if (! $admin->canManageTeacherProfile($teacher)) {
            return response()->json(['message' => 'You can only approve instructors in your department.'], 403);
        }

        if (CocSchool::isAccessAdminRole((string) $teacher->role) && ! $admin->isSuperAdmin()) {
            return response()->json(['message' => 'Only a super admin can change another admin account.'], 403);
        }

        $teacher->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $teacher->school_name = CocSchool::NAME;
        $teacher->save();

        return response()->json([
            'message' => 'Teacher approved.',
            'teacher' => [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'access_status' => $teacher->access_status,
                'department' => $teacher->department,
                'is_active' => $teacher->is_active,
            ],
        ]);
    }

    public function revoke(Request $request, string $teacherId): JsonResponse
    {
        $admin = $request->user();
        $teacher = $this->scopedTeacherProfile($admin, $teacherId);

        if ($teacher === null) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        if ($teacher->id === $admin->id) {
            return response()->json(['message' => 'You cannot revoke your own access here.'], 422);
        }

        if (! $admin->canManageTeacherProfile($teacher)) {
            return response()->json(['message' => 'You can only revoke instructors in your department.'], 403);
        }

        if (CocSchool::isSuperAdminRole((string) $teacher->role)) {
            return response()->json([
                'message' => 'Cannot revoke a super admin from Access control.',
            ], 422);
        }

        if ($teacher->role === CocSchool::ROLE_DEPT_ADMIN && ! $admin->isSuperAdmin()) {
            return response()->json([
                'message' => 'Only a super admin can revoke a department admin. Use Department admins.',
            ], 422);
        }

        if ($teacher->role === CocSchool::ROLE_DEPT_ADMIN) {
            return response()->json([
                'message' => 'Use Department admins to remove department admin power first.',
            ], 422);
        }

        $teacher->applyAccessStatus(CocSchool::ACCESS_REVOKED);
        $teacher->save();

        $teacher->user?->tokens()->delete();

        return response()->json([
            'message' => 'Teacher access revoked.',
            'teacher' => [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'access_status' => $teacher->access_status,
                'department' => $teacher->department,
                'is_active' => $teacher->is_active,
            ],
        ]);
    }

    public function departmentAdmins(Request $request): JsonResponse
    {
        $admins = TeacherProfile::query()
            ->with('user')
            ->where('role', CocSchool::ROLE_DEPT_ADMIN)
            ->where('school_name', CocSchool::NAME)
            ->orderBy('department')
            ->orderBy('full_name')
            ->get();

        return response()->json([
            'departments' => CocSchool::DEPARTMENTS,
            'admins' => $admins->map(fn (TeacherProfile $teacher) => [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'department' => $teacher->department,
                'access_status' => $teacher->access_status,
                'role' => $teacher->role,
            ])->values()->all(),
        ]);
    }

    public function makeDeptAdmin(Request $request, string $teacherId): JsonResponse
    {
        $validated = $request->validate([
            'department' => ['required', 'string', 'in:'.implode(',', CocSchool::DEPARTMENTS)],
        ]);

        $admin = $request->user();
        $teacher = TeacherProfile::query()->with('user')->find($teacherId);

        if ($teacher === null || $teacher->school_name !== CocSchool::NAME) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        if ($teacher->id === $admin->id) {
            return response()->json(['message' => 'You cannot change your own role here.'], 422);
        }

        if (CocSchool::isSuperAdminRole((string) $teacher->role)) {
            return response()->json(['message' => 'Cannot change another super admin role here.'], 422);
        }

        if (! $teacher->isApproved()) {
            return response()->json([
                'message' => 'Approve this instructor first, then assign them as department admin.',
            ], 422);
        }

        $department = CocSchool::normalizeDepartment($validated['department']);
        $teacher->role = CocSchool::ROLE_DEPT_ADMIN;
        $teacher->department = $department;
        $teacher->school_name = CocSchool::NAME;
        $teacher->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $teacher->save();

        return response()->json([
            'message' => "Assigned as {$department} department admin.",
            'teacher' => [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'role' => $teacher->role,
                'department' => $teacher->department,
                'access_status' => $teacher->access_status,
            ],
        ]);
    }

    public function destroy(Request $request, string $teacherId): JsonResponse
    {
        $admin = $request->user();
        $teacher = TeacherProfile::query()->with('user')->find($teacherId);

        if ($teacher === null || $teacher->school_name !== CocSchool::NAME) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        if ($teacher->id === $admin->id) {
            return response()->json(['message' => 'You cannot delete your own account here.'], 422);
        }

        if (CocSchool::isSuperAdminRole((string) $teacher->role)) {
            return response()->json(['message' => 'Cannot delete a super admin account.'], 422);
        }

        $fullName = $teacher->full_name;
        $email = $teacher->user?->email;

        $user = $teacher->user;
        if ($user !== null) {
            $user->tokens()->delete();
            $user->delete();
        } else {
            $teacher->delete();
        }

        return response()->json([
            'message' => 'Teacher account deleted.',
            'teacher' => [
                'id' => $teacherId,
                'full_name' => $fullName,
                'email' => $email,
            ],
        ]);
    }

    public function revokeDeptAdmin(Request $request, string $teacherId): JsonResponse
    {
        $admin = $request->user();
        $teacher = TeacherProfile::query()->with('user')->find($teacherId);

        if ($teacher === null || $teacher->school_name !== CocSchool::NAME) {
            return response()->json(['message' => 'Teacher not found.'], 404);
        }

        if ($teacher->id === $admin->id) {
            return response()->json(['message' => 'You cannot change your own role here.'], 422);
        }

        if ($teacher->role !== CocSchool::ROLE_DEPT_ADMIN) {
            return response()->json(['message' => 'That account is not a department admin.'], 422);
        }

        $teacher->role = CocSchool::ROLE_TEACHER;
        $teacher->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $teacher->save();

        return response()->json([
            'message' => 'Department admin power removed. They remain an approved instructor.',
            'teacher' => [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'role' => $teacher->role,
                'department' => $teacher->department,
                'access_status' => $teacher->access_status,
            ],
        ]);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function teacherSummaries(Request $request): array
    {
        $admin = $request->user();
        $teachers = $this->scope->schoolTeachersQuery($admin)->with('user')->get();

        return $teachers->map(function (TeacherProfile $teacher) use ($admin) {
            $teacherId = $teacher->id;
            $sectionCount = $this->scope->schoolWideSectionsQuery($admin)->where('owner_teacher_id', $teacherId)->count();
            $studentCount = $this->scope->schoolWideStudentsQuery($admin)->where('owner_teacher_id', $teacherId)->count();
            $subjectCount = $this->scope->schoolWideSubjectsQuery($admin)->where('owner_teacher_id', $teacherId)->count();
            $scanCount = $this->scope->schoolWideScanResultsQuery($admin)->where('owner_teacher_id', $teacherId)->count();
            $pendingReviewCount = $this->scope->schoolWideScanResultsQuery($admin)
                ->where('owner_teacher_id', $teacherId)
                ->where('needs_review', true)
                ->count();

            $status = 'active';
            if ($teacherId === $admin->id) {
                $status = 'you';
            } elseif ($teacher->access_status === CocSchool::ACCESS_PENDING) {
                $status = 'pending';
            } elseif ($teacher->access_status === CocSchool::ACCESS_REVOKED) {
                $status = 'revoked';
            } elseif ($sectionCount === 0 && $studentCount === 0 && $scanCount === 0) {
                $status = 'no_sync';
            }

            return [
                'id' => $teacher->id,
                'full_name' => $teacher->full_name,
                'email' => $teacher->user?->email,
                'role' => $teacher->role,
                'access_status' => $teacher->access_status,
                'department' => $teacher->department,
                'is_active' => $teacher->is_active,
                'section_count' => $sectionCount,
                'student_count' => $studentCount,
                'subject_count' => $subjectCount,
                'scan_count' => $scanCount,
                'pending_review_count' => $pendingReviewCount,
                'last_cloud_update' => $this->latestUpdateForTeacher($admin, $teacherId),
                'status' => $status,
            ];
        })->all();
    }

    private function scopedTeacherProfile($admin, string $teacherId): ?TeacherProfile
    {
        $teacher = $this->scope->schoolTeachersQuery($admin)
            ->with('user')
            ->where('id', $teacherId)
            ->first();

        return $teacher;
    }

    private function latestUpdateForTeacher($admin, string $teacherId): ?string
    {
        $timestamps = [];

        foreach (['sections', 'students', 'subjects', 'scan_results'] as $table) {
            $query = match ($table) {
                'sections' => $this->scope->schoolWideSectionsQuery($admin),
                'students' => $this->scope->schoolWideStudentsQuery($admin),
                'subjects' => $this->scope->schoolWideSubjectsQuery($admin),
                'scan_results' => $this->scope->schoolWideScanResultsQuery($admin),
            };

            $latest = $query
                ->where('owner_teacher_id', $teacherId)
                ->orderByDesc('updated_at')
                ->value('updated_at');

            if ($latest !== null) {
                $timestamps[] = (string) $latest;
            }
        }

        if ($timestamps === []) {
            return null;
        }

        sort($timestamps);

        return end($timestamps) ?: null;
    }
}
