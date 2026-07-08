<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Services\TeacherScopeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
    ) {}

    public function stats(Request $request): JsonResponse
    {
        $user = $request->user();

        $sectionCount = $this->scope->sectionsQuery($user)->count();
        $studentCount = $this->scope->studentsQuery($user)->count();
        $subjectCount = $this->scope->subjectsQuery($user)->count();
        $scanCount = $this->scope->scanResultsQuery($user)->count();
        $pendingReview = $this->scope
            ->scanResultsQuery($user)
            ->where('needs_review', true)
            ->count();

        return response()->json([
            'section_count' => $sectionCount,
            'student_count' => $studentCount,
            'subject_count' => $subjectCount,
            'scan_count' => $scanCount,
            'pending_review' => $pendingReview,
        ]);
    }

    public function lastUpdated(Request $request): JsonResponse
    {
        $user = $request->user();
        $timestamps = [];

        foreach (['sections', 'students', 'subjects', 'scan_results'] as $table) {
            $query = match ($table) {
                'sections' => $this->scope->sectionsQuery($user),
                'students' => $this->scope->studentsQuery($user),
                'subjects' => $this->scope->subjectsQuery($user),
                'scan_results' => $this->scope->scanResultsQuery($user),
            };

            $latest = $query->orderByDesc('updated_at')->value('updated_at');
            if ($latest !== null) {
                $timestamps[] = (string) $latest;
            }
        }

        sort($timestamps);

        return response()->json([
            'last_updated' => $timestamps === [] ? null : end($timestamps),
        ]);
    }
}
