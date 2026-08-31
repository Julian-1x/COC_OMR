<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\Subject;
use App\Services\TeacherScopeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class SubjectController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $subjects = $this->scope
            ->subjectsQuery($request->user())
            ->orderBy('name')
            ->get();

        return response()->json(['subjects' => $subjects]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $subject = $this->scope->subjectsQuery($request->user())->findOrFail($id);
        $this->authorize('view', $subject);

        return response()->json(['subject' => $subject]);
    }

    public function showByLocalId(Request $request, string $localId): JsonResponse
    {
        $subject = $this->scope
            ->subjectsQuery($request->user())
            ->where('local_id', $localId)
            ->firstOrFail();

        $this->authorize('view', $subject);

        return response()->json(['subject' => $subject]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Subject::class);

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
        ]);

        $subject = Subject::query()->updateOrCreate(
            [
                'owner_teacher_id' => $request->user()->id,
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
                'sync_status' => 'synced',
                'updated_at' => now(),
            ],
        );

        return response()->json(['subject' => $subject], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $subject = Subject::query()->findOrFail($id);
        $this->authorize('update', $subject);

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'answer_key' => ['sometimes', 'array'],
            'total_questions' => ['sometimes', 'integer', 'min:1'],
            'section_names' => ['nullable', 'array'],
            'section_qr_data' => ['nullable', 'array'],
            'exam_date' => ['nullable', 'date'],
            'passing_score' => ['sometimes', 'integer'],
            'use_partial_credit' => ['nullable', 'boolean'],
            'use_custom_layout' => ['nullable', 'boolean'],
            'options_count' => ['nullable', 'integer', 'min:2', 'max:5'],
            'layout_shape' => ['nullable', 'string', 'max:64'],
        ]);

        if (isset($validated['exam_date'])) {
            $validated['exam_date'] = Carbon::parse($validated['exam_date'])->toDateString();
        }

        $subject->fill($validated);
        $subject->updated_at = now();
        $subject->sync_status = 'synced';
        $subject->save();

        return response()->json(['subject' => $subject->fresh()]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $subject = Subject::query()->findOrFail($id);
        $this->authorize('delete', $subject);
        $subject->delete();

        return response()->json(['message' => 'Deleted.']);
    }
}
