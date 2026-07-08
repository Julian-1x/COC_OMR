<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\ScanResult;
use App\Services\SubjectResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

class ScanResultSyncController extends Controller
{
    public function __construct(
        private readonly SubjectResolver $subjectResolver,
    ) {}

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'id' => ['nullable', 'uuid'],
            'student_omr_id' => ['required', 'string', 'max:255'],
            'subject_local_id' => ['nullable', 'string', 'max:255'],
            'subject_name' => ['required', 'string', 'max:255'],
            'sheet_id' => ['nullable', 'string', 'max:255'],
            'detected_answers' => ['required', 'array'],
            'correctness_map' => ['required', 'array'],
            'score' => ['required', 'numeric'],
            'total_questions' => ['required', 'integer'],
            'confidence' => ['required', 'numeric'],
            'scan_time' => ['required', 'date'],
            'review_reasons' => ['nullable', 'array'],
            'flagged_questions' => ['nullable', 'array'],
            'manually_confirmed' => ['nullable', 'boolean'],
            'needs_review' => ['nullable', 'boolean'],
            'updated_at' => ['nullable', 'date'],
        ]);

        $user = $request->user();
        $ownerId = $user->id;
        $scanTime = Carbon::parse($validated['scan_time']);
        $updatedAt = isset($validated['updated_at'])
            ? Carbon::parse($validated['updated_at'])
            : now();

        $cloudSubjectId = $this->subjectResolver->resolveCloudSubjectId(
            $user,
            $validated['subject_local_id'] ?? null,
        );

        $payload = [
            'owner_teacher_id' => $ownerId,
            'student_omr_id' => $validated['student_omr_id'],
            'subject_id' => $cloudSubjectId,
            'subject_local_id' => $validated['subject_local_id'] ?? null,
            'subject_name' => $validated['subject_name'],
            'sheet_id' => $validated['sheet_id'] ?? null,
            'detected_answers' => $validated['detected_answers'],
            'correctness_map' => $validated['correctness_map'],
            'score' => $validated['score'],
            'total_questions' => $validated['total_questions'],
            'confidence' => $validated['confidence'],
            'scan_time' => $scanTime,
            'scanned_image_path' => null,
            'review_reasons' => $validated['review_reasons'] ?? null,
            'flagged_questions' => $validated['flagged_questions'] ?? null,
            'manually_confirmed' => $validated['manually_confirmed'] ?? false,
            'needs_review' => $validated['needs_review'] ?? false,
            'local_id' => $this->scanLocalId($validated),
            'sync_status' => 'synced',
            'updated_at' => $updatedAt,
        ];

        if (! empty($validated['id'])) {
            $existing = ScanResult::query()
                ->where('owner_teacher_id', $ownerId)
                ->where('id', $validated['id'])
                ->first();

            if ($existing !== null) {
                $this->authorize('update', $existing);
                $existing->update($payload);

                return response()->json([
                    'id' => $existing->id,
                    'scan_result' => $existing->fresh(),
                ]);
            }
        }

        $scanResult = ScanResult::query()->create($payload);

        return response()->json([
            'id' => $scanResult->id,
            'scan_result' => $scanResult->fresh(),
        ], 201);
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function scanLocalId(array $validated): string
    {
        $subject = $validated['subject_local_id'] ?? $validated['subject_name'];
        $scanTime = Carbon::parse($validated['scan_time'])->toIso8601String();

        return Str::of($validated['student_omr_id'])
            ->append('|', $subject, '|', $scanTime)
            ->toString();
    }
}
