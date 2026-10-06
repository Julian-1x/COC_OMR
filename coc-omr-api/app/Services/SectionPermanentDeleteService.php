<?php

namespace App\Services;

use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\Subject;
use Illuminate\Support\Str;

/**
 * Hard-delete an archived section and its roster/scores from the cloud.
 */
class SectionPermanentDeleteService
{
    /**
     * @return array{students: int, scan_results: int, deadlines: int, subjects_updated: int}
     */
    public function deleteArchived(Section $section): array
    {
        if ($section->archived_at === null) {
            throw new \InvalidArgumentException(
                'Archive the class first, then delete it permanently.',
            );
        }

        $ownerId = (string) $section->owner_teacher_id;
        $sectionName = (string) $section->name;
        $normalized = Str::lower(trim($sectionName));

        $students = Student::query()
            ->where('owner_teacher_id', $ownerId)
            ->whereRaw('LOWER(TRIM(section_name)) = ?', [$normalized])
            ->get(['id', 'omr_id']);

        $omrIds = $students->pluck('omr_id')->filter()->values()->all();
        $scansDeleted = 0;
        if ($omrIds !== []) {
            $scansDeleted = ScanResult::query()
                ->where('owner_teacher_id', $ownerId)
                ->whereIn('student_omr_id', $omrIds)
                ->delete();
        }

        $studentsDeleted = 0;
        if ($students->isNotEmpty()) {
            $studentsDeleted = Student::query()
                ->whereIn('id', $students->pluck('id'))
                ->delete();
        }

        $deadlinesDeleted = Deadline::query()
            ->where('owner_teacher_id', $ownerId)
            ->whereRaw('LOWER(TRIM(section_name)) = ?', [$normalized])
            ->delete();

        $subjectsUpdated = 0;
        $subjects = Subject::query()
            ->where('owner_teacher_id', $ownerId)
            ->get();
        foreach ($subjects as $subject) {
            $names = is_array($subject->section_names) ? $subject->section_names : [];
            $filtered = [];
            $changed = false;
            foreach ($names as $name) {
                if (Str::lower(trim((string) $name)) === $normalized) {
                    $changed = true;
                    continue;
                }
                $filtered[] = $name;
            }
            if (! $changed) {
                continue;
            }
            $subject->section_names = array_values($filtered);
            $subject->updated_at = now();
            $subject->sync_status = 'synced';
            $subject->save();
            $subjectsUpdated++;
        }

        $section->delete();

        return [
            'students' => $studentsDeleted,
            'scan_results' => $scansDeleted,
            'deadlines' => $deadlinesDeleted,
            'subjects_updated' => $subjectsUpdated,
        ];
    }
}
