<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\Deadline;
use App\Services\SubjectResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class DeadlineSyncController extends Controller
{
    public function __construct(
        private readonly SubjectResolver $subjectResolver,
    ) {}

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'local_id' => ['required', 'string', 'max:255'],
            'title' => ['required', 'string', 'max:255'],
            'section_name' => ['nullable', 'string', 'max:255'],
            'subject_local_id' => ['nullable', 'string', 'max:255'],
            'due_date' => ['required', 'date'],
            'is_completed' => ['nullable', 'boolean'],
            'updated_at' => ['nullable', 'date'],
        ]);

        $user = $request->user();
        $ownerId = $user->id;
        $updatedAt = isset($validated['updated_at'])
            ? Carbon::parse($validated['updated_at'])
            : now();

        $cloudSubjectId = $this->subjectResolver->resolveCloudSubjectId(
            $user,
            $validated['subject_local_id'] ?? null,
        );

        $deadline = Deadline::query()->updateOrCreate(
            [
                'owner_teacher_id' => $ownerId,
                'local_id' => $validated['local_id'],
            ],
            [
                'title' => $validated['title'],
                'section_name' => $validated['section_name'] ?? null,
                'subject_id' => $cloudSubjectId,
                'subject_local_id' => $validated['subject_local_id'] ?? null,
                'due_date' => Carbon::parse($validated['due_date']),
                'is_completed' => $validated['is_completed'] ?? false,
                'sync_status' => 'synced',
                'updated_at' => $updatedAt,
            ],
        );

        return response()->json([
            'id' => $deadline->id,
            'deadline' => $deadline->fresh(),
        ]);
    }
}
