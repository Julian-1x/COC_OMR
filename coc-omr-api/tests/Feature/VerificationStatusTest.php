<?php

namespace Tests\Feature;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class VerificationStatusTest extends TestCase
{
    use RefreshDatabase;

    public function test_unverified_email_returns_verified_false(): void
    {
        $user = User::query()->create([
            'name' => 'Pending',
            'email' => 'pending@example.com',
            'password' => Hash::make('Password1!'),
        ]);
        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Pending',
            'school_name' => CocSchool::NAME,
            'role' => 'teacher',
            'is_active' => false,
            'access_status' => CocSchool::ACCESS_PENDING,
        ]);

        $this->postJson('/api/email/verification-check', [
            'email' => 'pending@example.com',
        ])->assertOk()->assertExactJson([
            'verified' => false,
            'access_pending' => false,
        ]);
    }

    public function test_verified_pending_access_reports_access_pending(): void
    {
        $user = User::query()->create([
            'name' => 'Verified Pending',
            'email' => 'verified.pending@example.com',
            'password' => Hash::make('Password1!'),
            'email_verified_at' => now(),
        ]);
        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Verified Pending',
            'school_name' => CocSchool::NAME,
            'role' => 'teacher',
            'is_active' => false,
            'access_status' => CocSchool::ACCESS_PENDING,
        ]);

        $this->postJson('/api/email/verification-check', [
            'email' => 'verified.pending@example.com',
        ])->assertOk()->assertJson([
            'verified' => true,
            'access_pending' => true,
            'access_status' => CocSchool::ACCESS_PENDING,
        ]);
    }
}
