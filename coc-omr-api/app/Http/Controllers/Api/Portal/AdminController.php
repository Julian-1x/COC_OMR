<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Services\Auth\AuthEventLogger;
use App\Services\TeacherScopeService;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class AdminController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
        private readonly AuthEventLogger $authEvents,
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
     * Transfer the single school super-admin role to another approved teacher.
     * Requires password + typed recipient email + confirmation phrase.
     */
    public function transferSuperAdmin(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'target_teacher_id' => ['required', 'uuid'],
            'target_email' => ['required', 'email'],
            'current_password' => ['required', 'string'],
            'confirmation' => ['required', 'string'],
        ]);

        if (strtoupper(trim($validated['confirmation'])) !== 'TRANSFER') {
            return response()->json([
                'message' => 'Type TRANSFER exactly to confirm this change.',
            ], 422);
        }

        $admin = $request->user();
        if (! $admin || ! $admin->isSuperAdmin()) {
            return response()->json(['message' => 'Only the super admin can transfer this role.'], 403);
        }

        $passwordHash = $admin->getAuthPassword();
        $passwordOk = false;
        try {
            $passwordOk = is_string($passwordHash)
                && $passwordHash !== ''
                && Hash::check($validated['current_password'], $passwordHash);
        } catch (\Throwable $error) {
            report($error);
            $passwordOk = false;
        }
        if (! $passwordOk) {
            return response()->json([
                'message' => 'Current password is incorrect.',
            ], 422);
        }

        $target = TeacherProfile::query()->with('user')->find($validated['target_teacher_id']);
        if ($target === null || $target->school_name !== CocSchool::NAME) {
            return response()->json(['message' => 'Teacher not found at this school.'], 404);
        }

        if ($target->id === $admin->id) {
            return response()->json(['message' => 'You already hold the super admin role.'], 422);
        }

        $targetEmail = strtolower(trim((string) ($target->user?->email ?? '')));
        $typedEmail = strtolower(trim($validated['target_email']));
        if ($targetEmail === '' || $targetEmail !== $typedEmail) {
            return response()->json([
                'message' => 'Recipient email does not match the selected teacher. Type their full email to verify.',
            ], 422);
        }

        if (! $target->isApproved()) {
            return response()->json([
                'message' => 'Approve this instructor first, then transfer super admin.',
            ], 422);
        }

        // Target may already be super admin (stuck dual-super state after
        // bootstrap re-promoted the previous holder). Transfer still demotes you.
        $fromProfile = TeacherProfile::query()->find($admin->id);
        if ($fromProfile === null) {
            return response()->json(['message' => 'Your admin profile was not found.'], 422);
        }

        try {
            // One statement: demote every other COC super admin to teacher, keep
            // (or promote) the chosen recipient as the sole school super admin.
            $updated = DB::update(
                'UPDATE teacher_profiles
                 SET role = CASE
                        WHEN id = ? THEN ?
                        WHEN school_name = ? AND role IN (?, ?, ?) THEN ?
                        ELSE role
                     END,
                     school_name = CASE
                        WHEN id = ? THEN ?
                        ELSE school_name
                     END,
                     access_status = CASE
                        WHEN id = ? OR (school_name = ? AND role IN (?, ?, ?)) THEN ?
                        ELSE access_status
                     END,
                     is_active = CASE
                        WHEN id = ? OR (school_name = ? AND role IN (?, ?, ?)) THEN TRUE
                        ELSE is_active
                     END,
                     updated_at = ?
                 WHERE id = ?
                    OR (school_name = ? AND role IN (?, ?, ?))',
                [
                    $target->id,
                    CocSchool::ROLE_SUPER_ADMIN,
                    CocSchool::NAME,
                    CocSchool::ROLE_SUPER_ADMIN,
                    'admin',
                    'school_admin',
                    CocSchool::ROLE_TEACHER,
                    $target->id,
                    CocSchool::NAME,
                    $target->id,
                    CocSchool::NAME,
                    CocSchool::ROLE_SUPER_ADMIN,
                    'admin',
                    'school_admin',
                    CocSchool::ACCESS_APPROVED,
                    $target->id,
                    CocSchool::NAME,
                    CocSchool::ROLE_SUPER_ADMIN,
                    'admin',
                    'school_admin',
                    now(),
                    $target->id,
                    CocSchool::NAME,
                    CocSchool::ROLE_SUPER_ADMIN,
                    'admin',
                    'school_admin',
                ],
            );

            if ($updated < 1) {
                return response()->json([
                    'message' => 'Transfer failed: no teacher profiles were updated. Refresh and try again.',
                ], 500);
            }

            // Revoke sessions after roles commit so a token-delete glitch cannot
            // abort the role transfer (and so the current request can finish).
            try {
                $admin->tokens()->delete();
                $target->user?->tokens()->delete();
            } catch (\Throwable $tokenError) {
                report($tokenError);
            }

            try {
                $this->authEvents->record(
                    'super_admin_transferred',
                    (string) $admin->email,
                    $admin,
                    $request,
                    [
                        'from_teacher_id' => $fromProfile->id,
                        'to_teacher_id' => $target->id,
                        'to_email' => $targetEmail,
                    ],
                );
            } catch (\Throwable $logError) {
                report($logError);
            }
        } catch (\Throwable $error) {
            report($error);

            return response()->json([
                'message' => 'Transfer failed: '.$error->getMessage(),
            ], 500);
        }

        return response()->json([
            'message' => 'Super admin transferred. Sign in again. The new super admin must also sign in again.',
            'from' => [
                'id' => $fromProfile->id,
                'email' => $admin->email,
                'role' => CocSchool::ROLE_TEACHER,
            ],
            'to' => [
                'id' => $target->id,
                'email' => $targetEmail,
                'full_name' => $target->full_name,
                'role' => CocSchool::ROLE_SUPER_ADMIN,
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
