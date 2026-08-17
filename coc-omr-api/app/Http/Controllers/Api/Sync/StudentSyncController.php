<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Services\SyncSnapshotService;
use App\Support\PersonName;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class StudentSyncController extends Controller
{
    public function __construct(
        private readonly SyncSnapshotService $snapshotService,
    ) {}

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'school_id' => ['required', 'string', 'max:255'],
            'omr_id' => ['required', 'string', 'max:255'],
            'name' => ['required', 'string', 'max:255'],
            'section_name' => ['required', 'string', 'max:255'],
            'score' => ['nullable', 'numeric'],
            'answers' => ['nullable', 'array'],
            'scan_date' => ['nullable', 'date'],
            'confidence' => ['nullable', 'numeric'],
            'updated_at' => ['nullable', 'date'],
        ]);

        $ownerId = $request->user()->id;
        $schoolId = $this->snapshotService->normalizeSchoolId($validated['school_id']);
        $updatedAt = isset($validated['updated_at'])
            ? Carbon::parse($validated['updated_at'])
            : now();

        $student = Student::query()->updateOrCreate(
            [
                'owner_teacher_id' => $ownerId,
                'school_id' => $schoolId,
            ],
            [
                'omr_id' => $validated['omr_id'],
                'name' => PersonName::normalize($validated['name']),
                'section_name' => trim($validated['section_name']),
                'score' => $validated['score'] ?? null,
                'answers' => $validated['answers'] ?? null,
                'scan_date' => isset($validated['scan_date'])
                    ? Carbon::parse($validated['scan_date'])
                    : null,
                'confidence' => $validated['confidence'] ?? null,
                'local_id' => $validated['omr_id'],
                'sync_status' => 'synced',
                'updated_at' => $updatedAt,
            ],
        );

        return response()->json([
            'id' => $student->id,
            'student' => $student->fresh(),
        ]);
    }
}
