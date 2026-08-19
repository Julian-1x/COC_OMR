<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Services\SyncSnapshotService;
use App\Services\TeacherScopeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class StudentController extends Controller
{
    public function __construct(
        private readonly TeacherScopeService $scope,
        private readonly SyncSnapshotService $snapshotService,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $query = $this->scope->studentsQuery($request->user())->orderBy('name');

        if ($sectionName = $request->string('section_name')->toString()) {
            $query->where('section_name', $sectionName);
        }

        $query->select([
            'id',
            'owner_teacher_id',
            'school_id',
            'omr_id',
            'name',
            'section_name',
            'score',
            'scan_date',
            'confidence',
            'local_id',
            'sync_status',
            'created_at',
            'updated_at',
        ]);

        return response()->json([
            'students' => $query->get(),
        ]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $student = $this->scope->studentsQuery($request->user())->findOrFail($id);
        $this->authorize('view', $student);

        return response()->json(['student' => $student]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Student::class);

        $validated = $request->validate([
            'school_id' => ['required', 'string', 'max:255'],
            'omr_id' => ['required', 'string', 'max:255'],
            'name' => ['required', 'string', 'max:255'],
            'section_name' => ['required', 'string', 'max:255'],
        ]);

        $ownerId = $request->user()->id;
        $schoolId = $this->snapshotService->normalizeSchoolId($validated['school_id']);

        $student = Student::query()->updateOrCreate(
            [
                'owner_teacher_id' => $ownerId,
                'school_id' => $schoolId,
            ],
            [
                'omr_id' => $validated['omr_id'],
                'name' => trim($validated['name']),
                'section_name' => trim($validated['section_name']),
                'local_id' => $validated['omr_id'],
                'sync_status' => 'synced',
                'updated_at' => now(),
            ],
        );

        return response()->json(['student' => $student], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $student = Student::query()->findOrFail($id);
        $this->authorize('update', $student);

        $validated = $request->validate([
            'school_id' => ['sometimes', 'string', 'max:255'],
            'omr_id' => ['sometimes', 'string', 'max:255'],
            'name' => ['sometimes', 'string', 'max:255'],
            'section_name' => ['sometimes', 'string', 'max:255'],
            'score' => ['nullable', 'numeric'],
            'answers' => ['nullable', 'array'],
        ]);

        if (isset($validated['school_id'])) {
            $validated['school_id'] = $this->snapshotService->normalizeSchoolId($validated['school_id']);
        }

        $student->fill($validated);
        $student->updated_at = now();
        $student->sync_status = 'synced';
        $student->save();

        return response()->json(['student' => $student->fresh()]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $student = Student::query()->findOrFail($id);
        $this->authorize('delete', $student);
        $student->delete();

        return response()->json(['message' => 'Deleted.']);
    }
}
