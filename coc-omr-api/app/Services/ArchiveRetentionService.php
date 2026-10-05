<?php

namespace App\Services;

use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Permanently delete soft-archived sections/students after the retention window.
 * Default: 4 months from archived_at (restore before then).
 */
class ArchiveRetentionService
{
    public static function retentionMonths(): int
    {
        $months = (int) config('omr.archive_retention_months', 4);

        return max(1, $months);
    }

    public static function cutoff(): \Carbon\CarbonInterface
    {
        return now()->subMonthsNoOverflow(self::retentionMonths());
    }

    /**
     * @return array{students: int, sections: int, scan_results: int, deadlines: int}
     */
    public function purgeExpired(?string $ownerTeacherId = null): array
    {
        $cutoff = self::cutoff();
        $studentsDeleted = 0;
        $sectionsDeleted = 0;
        $scansDeleted = 0;
        $deadlinesDeleted = 0;

        DB::transaction(function () use (
            $cutoff,
            $ownerTeacherId,
            &$studentsDeleted,
            &$sectionsDeleted,
            &$scansDeleted,
            &$deadlinesDeleted,
        ) {
            $studentQuery = Student::query()
                ->whereNotNull('archived_at')
                ->where('archived_at', '<=', $cutoff);
            if ($ownerTeacherId !== null) {
                $studentQuery->where('owner_teacher_id', $ownerTeacherId);
            }

            $expiredStudents = $studentQuery->get(['id', 'owner_teacher_id', 'omr_id']);
            if ($expiredStudents->isNotEmpty()) {
                $byOwner = $expiredStudents->groupBy('owner_teacher_id');
                foreach ($byOwner as $ownerId => $rows) {
                    $omrIds = $rows->pluck('omr_id')->filter()->values()->all();
                    if ($omrIds !== []) {
                        $scansDeleted += ScanResult::query()
                            ->where('owner_teacher_id', $ownerId)
                            ->whereIn('student_omr_id', $omrIds)
                            ->delete();
                    }
                }
                $studentsDeleted = Student::query()
                    ->whereIn('id', $expiredStudents->pluck('id'))
                    ->delete();
            }

            $sectionQuery = Section::query()
                ->whereNotNull('archived_at')
                ->where('archived_at', '<=', $cutoff);
            if ($ownerTeacherId !== null) {
                $sectionQuery->where('owner_teacher_id', $ownerTeacherId);
            }

            $expiredSections = $sectionQuery->get(['id', 'owner_teacher_id', 'name']);
            if ($expiredSections->isNotEmpty()) {
                foreach ($expiredSections as $section) {
                    $deadlinesDeleted += Deadline::query()
                        ->where('owner_teacher_id', $section->owner_teacher_id)
                        ->whereRaw('LOWER(TRIM(section_name)) = ?', [mb_strtolower(trim((string) $section->name))])
                        ->delete();
                }
                $sectionsDeleted = Section::query()
                    ->whereIn('id', $expiredSections->pluck('id'))
                    ->delete();
            }
        });

        if ($studentsDeleted + $sectionsDeleted > 0) {
            Log::info('archive_retention_purged', [
                'owner_teacher_id' => $ownerTeacherId,
                'cutoff' => $cutoff->toIso8601String(),
                'students' => $studentsDeleted,
                'sections' => $sectionsDeleted,
                'scan_results' => $scansDeleted,
                'deadlines' => $deadlinesDeleted,
            ]);
        }

        return [
            'students' => $studentsDeleted,
            'sections' => $sectionsDeleted,
            'scan_results' => $scansDeleted,
            'deadlines' => $deadlinesDeleted,
        ];
    }
}
