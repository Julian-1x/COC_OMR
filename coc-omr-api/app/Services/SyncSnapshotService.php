<?php

namespace App\Services;

use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\Subject;
use App\Models\User;
use Illuminate\Support\Str;

class SyncSnapshotService
{
    /**
     * Mirrors mobile pull logic in supabase_sync_service.dart.
     */
    public function buildForTeacher(User $user): array
    {
        $ownerId = $user->id;

        $sections = Section::query()
            ->where('owner_teacher_id', $ownerId)
            ->whereNull('archived_at')
            ->orderBy('name')
            ->get();

        $activeSectionNames = $sections
            ->pluck('name')
            ->filter(fn (string $name) => $name !== '')
            ->values()
            ->all();

        if ($activeSectionNames === []) {
            return [
                'sections' => $sections,
                'students' => collect(),
                'subjects' => collect(),
                'scan_results' => collect(),
                'deadlines' => collect(),
            ];
        }

        $students = Student::query()
            ->where('owner_teacher_id', $ownerId)
            ->whereIn('section_name', $activeSectionNames)
            ->orderBy('name')
            ->get();

        $activeOmrIds = $students->pluck('omr_id')->all();
        $activeSectionSet = collect($activeSectionNames)
            ->map(fn (string $name) => $this->normalizeSectionName($name))
            ->flip();

        $allSubjects = Subject::query()
            ->where('owner_teacher_id', $ownerId)
            ->orderBy('name')
            ->get();

        $subjects = $allSubjects->filter(function (Subject $subject) use ($activeSectionSet) {
            $names = $subject->section_names;
            if ($names === null || $names === []) {
                return true;
            }

            foreach ($names as $name) {
                if ($activeSectionSet->has($this->normalizeSectionName((string) $name))) {
                    return true;
                }
            }

            return false;
        })->values();

        $scanResults = collect();
        if ($activeOmrIds !== []) {
            $scanResults = ScanResult::query()
                ->where('owner_teacher_id', $ownerId)
                ->whereIn('student_omr_id', $activeOmrIds)
                ->orderBy('scan_time')
                ->get();
        }

        $deadlines = Deadline::query()
            ->where('owner_teacher_id', $ownerId)
            ->whereIn('section_name', $activeSectionNames)
            ->orderBy('due_date')
            ->get();

        return [
            'sections' => $sections,
            'students' => $students,
            'subjects' => $subjects,
            'scan_results' => $scanResults,
            'deadlines' => $deadlines,
        ];
    }

    public function normalizeSchoolId(string $schoolId): string
    {
        return Str::upper(trim($schoolId));
    }

    public function normalizeSectionName(string $name): string
    {
        return Str::lower(trim($name));
    }
}
