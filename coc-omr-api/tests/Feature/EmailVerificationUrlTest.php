<?php

namespace Tests\Feature;

use App\Models\TeacherProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\URL;
use Tests\TestCase;

class EmailVerificationUrlTest extends TestCase
{
    use RefreshDatabase;

    public function test_verification_link_with_platform_query_passes_signature_check(): void
    {
        $user = User::query()->create([
            'name' => 'Test Teacher',
            'email' => 'teacher@example.com',
            'password' => bcrypt('password'),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Test Teacher',
            'school_name' => 'Test School',
            'role' => 'teacher',
            'is_active' => true,
        ]);

        $url = URL::temporarySignedRoute(
            'verification.verify',
            now()->addHour(),
            [
                'id' => $user->id,
                'hash' => sha1($user->email),
                'platform' => 'web',
            ],
        );

        $this->get($url)->assertRedirect();
    }
}
