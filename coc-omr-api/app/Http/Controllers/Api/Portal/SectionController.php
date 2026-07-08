<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\Section;
use App\Services\TeacherScopeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SectionController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $query = $this->scope->sectionsQuery($request->user())->orderBy('name');

        if ($request->boolean('archived')) {
            $query->whereNotNull('archived_at');
        } elseif ($request->has('archived') && ! $request->boolean('archived')) {
            $query->whereNull('archived_at');
        }

        if ($schoolYear = $request->string('school_year')->toString()) {
            $query->where('school_year', $schoolYear);
        }

        return response()->json([
            'sections' => $query->get(),
        ]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $section = $this->scope->sectionsQuery($request->user())->findOrFail($id);
        $this->authorize('view', $section);

        return response()->json(['section' => $section]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Section::class);

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'student_count' => ['nullable', 'integer'],
            'school_year' => ['nullable', 'string', 'max:255'],
            'term_label' => ['nullable', 'string', 'max:255'],
        ]);

        $ownerId = $request->user()->id;

        $section = Section::query()->updateOrCreate(
            [
                'owner_teacher_id' => $ownerId,
                'name' => $validated['name'],
            ],
            [
                'student_count' => $validated['student_count'] ?? null,
                'school_year' => $validated['school_year'] ?? null,
                'term_label' => $validated['term_label'] ?? null,
                'local_id' => $validated['name'],
                'sync_status' => 'synced',
                'updated_at' => now(),
            ],
        );

        return response()->json(['section' => $section], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $section = Section::query()->findOrFail($id);
        $this->authorize('update', $section);

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'teacher' => ['nullable', 'string', 'max:255'],
            'student_count' => ['nullable', 'integer'],
            'school_year' => ['nullable', 'string', 'max:255'],
            'term_label' => ['nullable', 'string', 'max:255'],
            'archived_at' => ['nullable', 'date'],
        ]);

        $section->fill($validated);
        $section->updated_at = now();
        $section->sync_status = 'synced';
        $section->save();

        return response()->json(['section' => $section->fresh()]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $section = Section::query()->findOrFail($id);
        $this->authorize('delete', $section);
        $section->delete();

        return response()->json(['message' => 'Deleted.']);
    }
}
