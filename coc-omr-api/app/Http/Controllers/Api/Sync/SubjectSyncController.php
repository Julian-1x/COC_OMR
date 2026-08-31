<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\Subject;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class SubjectSyncController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'local_id' => ['required', 'string', 'max:255'],
            'name' => ['required', 'string', 'max:255'],
            'answer_key' => ['required', 'array'],
            'total_questions' => ['required', 'integer', 'min:1'],
            'section_names' => ['nullable', 'array'],
            'section_qr_data' => ['nullable', 'array'],
            'exam_date' => ['nullable', 'date'],
            'passing_score' => ['required', 'integer'],
            'use_partial_credit' => ['nullable', 'boolean'],
            'use_custom_layout' => ['nullable', 'boolean'],
            'options_count' => ['nullable', 'integer', 'min:2', 'max:5'],
            'layout_shape' => ['nullable', 'string', 'max:64'],
            'custom_layout_id' => ['nullable', 'string', 'max:64'],
            'custom_grid_columns' => ['nullable', 'integer', 'min:1', 'max:10'],
            'custom_grid_rows' => ['nullable', 'integer', 'min:1', 'max:30'],
            'updated_at' => ['nullable', 'date'],
        ]);

        $ownerId = $request->user()->id;
        $updatedAt = isset($validated['updated_at'])
            ? Carbon::parse($validated['updated_at'])
            : now();

        $subject = Subject::query()->updateOrCreate(
            [
                'owner_teacher_id' => $ownerId,
                'local_id' => $validated['local_id'],
            ],
            [
                'name' => $validated['name'],
                'answer_key' => $validated['answer_key'],
                'total_questions' => $validated['total_questions'],
                'section_names' => $validated['section_names'] ?? null,
                'section_qr_data' => $validated['section_qr_data'] ?? [],
                'exam_date' => isset($validated['exam_date'])
                    ? Carbon::parse($validated['exam_date'])->toDateString()
                    : null,
                'passing_score' => $validated['passing_score'],
                'use_partial_credit' => $validated['use_partial_credit'] ?? false,
                'use_custom_layout' => $validated['use_custom_layout'] ?? false,
                'options_count' => $validated['options_count'] ?? 5,
                'layout_shape' => $validated['layout_shape'] ?? 'lengthwise_full',
                'custom_layout_id' => $validated['custom_layout_id'] ?? null,
                'custom_grid_columns' => $validated['custom_grid_columns'] ?? null,
                'custom_grid_rows' => $validated['custom_grid_rows'] ?? null,
                'sync_status' => 'synced',
                'updated_at' => $updatedAt,
            ],
        );

        return response()->json([
            'id' => $subject->id,
            'subject' => $subject->fresh(),
        ]);
    }
}
