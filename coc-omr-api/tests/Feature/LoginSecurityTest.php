<?php

namespace Tests\Feature;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class LoginSecurityTest extends TestCase
{
    use RefreshDatabase;

    public function test_login_locks_account_after_repeated_failures(): void
    {
        config(['security.login.max_failures_before_lock' => 3]);
        config(['security.captcha.enabled' => false]);

        $user = User::query()->create([
            'name' => 'Test Teacher',
            'email' => 'teacher@coc.edu.ph',
            'password' => Hash::make('CorrectPass1!'),
            'email_verified_at' => now(),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Test Teacher',
            'school_name' => CocSchool::NAME,
            'department' => CocSchool::DEPARTMENTS[0],
            'role' => 'teacher',
            'is_active' => true,
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);

        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/api/login', [
                'email' => 'teacher@coc.edu.ph',
                'password' => 'wrong',
            ])->assertStatus(422);
        }

        $user->refresh();
        $this->assertNotNull($user->locked_until);
        $this->assertTrue($user->locked_until->isFuture());

        $this->postJson('/api/login', [
            'email' => 'teacher@coc.edu.ph',
            'password' => 'CorrectPass1!',
        ])->assertStatus(429);
    }

    public function test_successful_login_clears_lockout_counters(): void
    {
        config(['security.captcha.enabled' => false]);

        $user = User::query()->create([
            'name' => 'Test Teacher',
            'email' => 'teacher2@coc.edu.ph',
            'password' => Hash::make('CorrectPass1!'),
            'email_verified_at' => now(),
            'failed_login_attempts' => 2,
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Test Teacher',
            'school_name' => CocSchool::NAME,
            'department' => CocSchool::DEPARTMENTS[0],
            'role' => 'teacher',
            'is_active' => true,
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);

        $this->postJson('/api/login', [
            'email' => 'teacher2@coc.edu.ph',
            'password' => 'CorrectPass1!',
        ])->assertOk()->assertJsonStructure(['token', 'user']);

        $user->refresh();
        $this->assertSame(0, $user->failed_login_attempts);
        $this->assertNull($user->locked_until);
    }
}
