<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\ScanResult;
use App\Services\SubjectResolver;
use App\Services\TeacherScopeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class ScanResultController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
        private readonly SubjectResolver $subjectResolver,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $results = $this->scope
            ->scanResultsQuery($request->user())
            ->orderByDesc('scan_time')
            ->get();

        return response()->json(['scan_results' => $results]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $result = $this->scope->scanResultsQuery($request->user())->findOrFail($id);
        $this->authorize('view', $result);

        return response()->json(['scan_result' => $result]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', ScanResult::class);

        $validated = $request->validate([
            'student_omr_id' => ['required', 'string', 'max:255'],
            'subject_local_id' => ['nullable', 'string', 'max:255'],
            'subject_name' => ['required', 'string', 'max:255'],
            'detected_answers' => ['required', 'array'],
            'correctness_map' => ['required', 'array'],
            'score' => ['required', 'numeric'],
            'total_questions' => ['required', 'integer'],
            'confidence' => ['required', 'numeric'],
            'scan_time' => ['required', 'date'],
            'needs_review' => ['nullable', 'boolean'],
        ]);

        $user = $request->user();

        $result = ScanResult::query()->create([
            'owner_teacher_id' => $user->id,
            'student_omr_id' => $validated['student_omr_id'],
            'subject_id' => $this->subjectResolver->resolveCloudSubjectId(
                $user,
                $validated['subject_local_id'] ?? null,
            ),
            'subject_local_id' => $validated['subject_local_id'] ?? null,
            'subject_name' => $validated['subject_name'],
            'detected_answers' => $validated['detected_answers'],
            'correctness_map' => $validated['correctness_map'],
            'score' => $validated['score'],
            'total_questions' => $validated['total_questions'],
            'confidence' => $validated['confidence'],
            'scan_time' => Carbon::parse($validated['scan_time']),
            'needs_review' => $validated['needs_review'] ?? false,
            'sync_status' => 'synced',
        ]);

        return response()->json(['scan_result' => $result], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $result = ScanResult::query()->findOrFail($id);
        $this->authorize('update', $result);

        $validated = $request->validate([
            'manually_confirmed' => ['nullable', 'boolean'],
            'needs_review' => ['nullable', 'boolean'],
            'review_reasons' => ['nullable', 'array'],
            'flagged_questions' => ['nullable', 'array'],
        ]);

        $result->fill($validated);
        $result->updated_at = now();
        $result->sync_status = 'synced';
        $result->save();

        return response()->json(['scan_result' => $result->fresh()]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $result = ScanResult::query()->findOrFail($id);
        $this->authorize('delete', $result);
        $result->delete();

        return response()->json(['message' => 'Deleted.']);
    }
}
