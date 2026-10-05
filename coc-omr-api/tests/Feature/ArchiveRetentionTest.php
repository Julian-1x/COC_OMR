<?php

namespace Tests\Feature;

use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\User;
use App\Services\ArchiveRetentionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ArchiveRetentionTest extends TestCase
{
    use RefreshDatabase;

    public function test_purges_archived_students_and_sections_past_retention(): void
    {
        $teacher = User::query()->create([
            'id' => (string) Str::uuid(),
            'name' => 'Archive Teacher',
            'email' => 'archive.teacher@example.com',
            'password' => bcrypt('Password1!'),
            'email_verified_at' => now(),
        ]);

        $oldSection = Section::query()->create([
            'id' => (string) Str::uuid(),
            'owner_teacher_id' => $teacher->id,
            'name' => 'OLD-SEC',
            'archived_at' => now()->subMonths(5),
            'sync_status' => 'synced',
        ]);

        $freshSection = Section::query()->create([
            'id' => (string) Str::uuid(),
            'owner_teacher_id' => $teacher->id,
            'name' => 'FRESH-SEC',
            'archived_at' => now()->subMonth(),
            'sync_status' => 'synced',
        ]);

        $oldStudent = Student::query()->create([
            'id' => (string) Str::uuid(),
            'owner_teacher_id' => $teacher->id,
            'omr_id' => '0001',
            'name' => 'Old Student',
            'section_name' => 'OLD-SEC',
            'archived_at' => now()->subMonths(5),
            'sync_status' => 'synced',
        ]);

        ScanResult::query()->create([
            'id' => (string) Str::uuid(),
            'owner_teacher_id' => $teacher->id,
            'student_omr_id' => '0001',
            'subject_name' => 'Exam',
            'detected_answers' => [],
            'correctness_map' => [],
            'score' => 0,
            'total_questions' => 10,
            'sync_status' => 'synced',
        ]);

        $summary = app(ArchiveRetentionService::class)->purgeExpired($teacher->id);

        $this->assertSame(1, $summary['sections']);
        $this->assertSame(1, $summary['students']);
        $this->assertSame(1, $summary['scan_results']);
        $this->assertDatabaseMissing('sections', ['id' => $oldSection->id]);
        $this->assertDatabaseMissing('students', ['id' => $oldStudent->id]);
        $this->assertDatabaseHas('sections', ['id' => $freshSection->id]);
    }
}
