<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\Deadline;
use App\Models\Section;
use App\Models\Subject;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

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

        // Older phone builds stripped section_names on archive. Re-attach using
        // surviving QR map keys and deadlines so restore brings answer keys back.
        $repairedSubjects = $this->reattachSectionToSubjects(
            $ownerId,
            $section->name,
        );

        return response()->json([
            'id' => $section->id,
            'section' => $section->fresh(),
            'repaired_subjects' => $repairedSubjects,
        ]);
    }

    /**
     * @return int Number of subjects updated
     */
    private function reattachSectionToSubjects(string $ownerId, string $sectionName): int
    {
        $target = $this->normalizeSectionName($sectionName);
        if ($target === '') {
            return 0;
        }

        $subjectIdsFromDeadlines = Deadline::query()
            ->where('owner_teacher_id', $ownerId)
            ->whereRaw('LOWER(TRIM(section_name)) = ?', [$target])
            ->get(['subject_id', 'subject_local_id']);

        $localIds = [];
        $uuids = [];
        foreach ($subjectIdsFromDeadlines as $deadline) {
            if (is_string($deadline->subject_local_id) && $deadline->subject_local_id !== '') {
                $localIds[$deadline->subject_local_id] = true;
            }
            if (is_string($deadline->subject_id) && $deadline->subject_id !== '') {
                $uuids[$deadline->subject_id] = true;
            }
        }

        $updated = 0;
        $subjects = Subject::query()
            ->where('owner_teacher_id', $ownerId)
            ->get();

        foreach ($subjects as $subject) {
            $names = is_array($subject->section_names) ? $subject->section_names : [];
            $alreadyLinked = false;
            foreach ($names as $name) {
                if ($this->normalizeSectionName((string) $name) === $target) {
                    $alreadyLinked = true;
                    break;
                }
            }
            if ($alreadyLinked) {
                continue;
            }

            $shouldAttach = false;

            $qr = is_array($subject->section_qr_data) ? $subject->section_qr_data : [];
            foreach (array_keys($qr) as $qrSection) {
                if ($this->normalizeSectionName((string) $qrSection) === $target) {
                    $shouldAttach = true;
                    break;
                }
            }

            if (! $shouldAttach) {
                $localId = (string) ($subject->local_id ?? '');
                $id = (string) $subject->id;
                if (($localId !== '' && isset($localIds[$localId])) ||
                    ($id !== '' && isset($uuids[$id]))) {
                    $shouldAttach = true;
                }
            }

            if (! $shouldAttach) {
                continue;
            }

            $names[] = $sectionName;
            $subject->section_names = array_values($names);
            $subject->updated_at = now();
            $subject->sync_status = 'synced';
            $subject->save();
            $updated++;
        }

        return $updated;
    }

    private function normalizeSectionName(string $name): string
    {
        return Str::lower(trim($name));
    }
}
