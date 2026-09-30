<?php

namespace Tests\Feature;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Notifications\AccountApprovedNotification;
use App\Support\CocSchool;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AccountApprovedEmailTest extends TestCase
{
    use RefreshDatabase;

    private function makeAdmin(): User
    {
        $user = User::query()->create([
            'name' => 'Super Admin',
            'email' => 'super@coc.edu.ph',
            'password' => Hash::make('CorrectPass1!'),
            'email_verified_at' => now(),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Super Admin',
            'school_name' => CocSchool::NAME,
            'department' => CocSchool::DEPARTMENTS[0],
            'role' => CocSchool::ROLE_SUPER_ADMIN,
            'is_active' => true,
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);

        return $user->fresh('teacherProfile');
    }

    private function makePendingTeacher(string $email = 'pending@coc.edu.ph'): User
    {
        $user = User::query()->create([
            'name' => 'Pending Teacher',
            'email' => $email,
            'password' => Hash::make('CorrectPass1!'),
            'email_verified_at' => now(),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Pending Teacher',
            'school_name' => CocSchool::NAME,
            'department' => CocSchool::DEPARTMENTS[0],
            'role' => CocSchool::ROLE_TEACHER,
            'is_active' => false,
            'access_status' => CocSchool::ACCESS_PENDING,
        ]);

        return $user->fresh('teacherProfile');
    }

    public function test_approve_sends_account_approved_email(): void
    {
        Notification::fake();
        config(['services.brevo.api_key' => '']);

        $admin = $this->makeAdmin();
        $teacher = $this->makePendingTeacher();

        Sanctum::actingAs($admin);

        $this->postJson("/api/admin/teachers/{$teacher->id}/approve")
            ->assertOk()
            ->assertJsonPath('email_sent', true)
            ->assertJsonFragment([
                'message' => 'Teacher approved. We emailed them that they can sign in.',
            ]);

        Notification::assertSentTo($teacher, AccountApprovedNotification::class);
        $this->assertSame(CocSchool::ACCESS_APPROVED, $teacher->fresh()->teacherProfile?->access_status);
    }

    public function test_reapprove_does_not_resend_email(): void
    {
        Notification::fake();
        config(['services.brevo.api_key' => '']);

        $admin = $this->makeAdmin();
        $teacher = $this->makePendingTeacher('already@coc.edu.ph');
        $teacher->teacherProfile?->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $teacher->teacherProfile?->save();

        Sanctum::actingAs($admin);

        $this->postJson("/api/admin/teachers/{$teacher->id}/approve")
            ->assertOk()
            ->assertJsonPath('email_sent', null);

        Notification::assertNothingSent();
    }
}
