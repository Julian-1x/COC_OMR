<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\Section;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class SectionSyncController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'teacher' => ['nullable', 'string', 'max:255'],
            'student_count' => ['nullable', 'integer'],
            'school_year' => ['nullable', 'string', 'max:255'],
            'term_label' => ['nullable', 'string', 'max:255'],
            'archived_at' => ['nullable', 'date'],
            'updated_at' => ['nullable', 'date'],
        ]);

        $ownerId = $request->user()->id;
        $updatedAt = isset($validated['updated_at'])
            ? Carbon::parse($validated['updated_at'])
            : now();

        $section = Section::query()->updateOrCreate(
            [
                'owner_teacher_id' => $ownerId,
                'name' => $validated['name'],
            ],
            [
                'teacher' => $validated['teacher'] ?? null,
                'student_count' => $validated['student_count'] ?? null,
                'school_year' => $validated['school_year'] ?? null,
                'term_label' => $validated['term_label'] ?? null,
                'archived_at' => isset($validated['archived_at'])
                    ? Carbon::parse($validated['archived_at'])
                    : null,
                'local_id' => $validated['name'],
                'sync_status' => 'synced',
                'updated_at' => $updatedAt,
            ],
        );

        return response()->json([
            'id' => $section->id,
            'section' => $section->fresh(),
        ]);
    }

    public function archive(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'school_year' => ['nullable', 'string', 'max:255'],
            'term_label' => ['nullable', 'string', 'max:255'],
        ]);

        $ownerId = $request->user()->id;
        $section = Section::query()
            ->where('owner_teacher_id', $ownerId)
            ->where('name', $validated['name'])
            ->first();

        if ($section === null) {
            return response()->json([
                'message' => 'Section was not found in the cloud. Sync first, then archive.',
            ], 404);
        }

        $this->authorize('archive', $section);

        $archivedAt = now();
        $section->fill([
            'archived_at' => $archivedAt,
            'updated_at' => $archivedAt,
        ]);

        if (! empty($validated['school_year'])) {
            $section->school_year = $validated['school_year'];
        }
        if (! empty($validated['term_label'])) {
            $section->term_label = $validated['term_label'];
        }

        $section->save();

        return response()->json([
            'id' => $section->id,
            'section' => $section->fresh(),
        ]);
    }

    public function unarchive(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
        ]);

        $ownerId = $request->user()->id;
        $section = Section::query()
            ->where('owner_teacher_id', $ownerId)
            ->where('name', $validated['name'])
            ->first();

        if ($section === null) {
            return response()->json([
                'message' => 'Section was not found in the cloud.',
            ], 404);
        }

        $this->authorize('unarchive', $section);

        $section->fill([
            'archived_at' => null,
            'updated_at' => now(),
        ]);
        $section->save();

        return response()->json([
            'id' => $section->id,
            'section' => $section->fresh(),
        ]);
    }
}
