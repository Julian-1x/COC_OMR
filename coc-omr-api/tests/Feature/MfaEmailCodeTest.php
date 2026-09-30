<?php

namespace Tests\Feature;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Notifications\MfaEmailCodeNotification;
use App\Services\Auth\MfaService;
use App\Support\CocSchool;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class MfaEmailCodeTest extends TestCase
{
    use RefreshDatabase;

    private function makeMfaUser(string $email = 'admin@coc.edu.ph'): User
    {
        $user = User::query()->create([
            'name' => 'Dept Admin',
            'email' => $email,
            'password' => Hash::make('CorrectPass1!'),
            'email_verified_at' => now(),
            'two_factor_secret' => encrypt('JBSWY3DPEHPK3PXP'),
            'two_factor_confirmed_at' => now(),
            'two_factor_recovery_codes' => encrypt(json_encode(['ABCD-EFGH'], JSON_THROW_ON_ERROR)),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Dept Admin',
            'school_name' => CocSchool::NAME,
            'department' => CocSchool::DEPARTMENTS[0],
            'role' => 'dept_admin',
            'is_active' => true,
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);

        return $user->fresh('teacherProfile');
    }

    public function test_email_code_send_and_login_success(): void
    {
        Notification::fake();
        config(['security.captcha.enabled' => false]);

        $user = $this->makeMfaUser();
        /** @var MfaService $mfa */
        $mfa = app(MfaService::class);
        $ticket = $mfa->issueChallengeTicket($user);

        $this->postJson('/api/login/mfa/email-code', [
            'mfa_ticket' => $ticket,
        ])->assertOk()
            ->assertJsonPath('ok', true)
            ->assertJsonStructure(['message', 'email_hint', 'resend_after_seconds']);

        Notification::assertSentTo($user, MfaEmailCodeNotification::class);

        $code = null;
        Notification::assertSentTo(
            $user,
            MfaEmailCodeNotification::class,
            function (MfaEmailCodeNotification $notification) use (&$code): bool {
                $code = $notification->plainCode();

                return true;
            },
        );
        $this->assertNotNull($code);

        $this->postJson('/api/login/mfa', [
            'mfa_ticket' => $ticket,
            'code' => $code,
            'device_name' => 'test',
        ])->assertOk()->assertJsonStructure(['token', 'user']);
    }

    public function test_email_code_resend_is_throttled(): void
    {
        Notification::fake();
        config([
            'security.captcha.enabled' => false,
            'security.mfa.email_otp_resend_seconds' => 60,
        ]);

        $user = $this->makeMfaUser('admin2@coc.edu.ph');
        $ticket = app(MfaService::class)->issueChallengeTicket($user);

        $this->postJson('/api/login/mfa/email-code', ['mfa_ticket' => $ticket])->assertOk();
        $this->postJson('/api/login/mfa/email-code', ['mfa_ticket' => $ticket])
            ->assertStatus(422)
            ->assertJsonFragment([
                'message' => 'Wait 60 seconds before requesting another email code.',
            ]);
    }

    public function test_wrong_email_code_fails(): void
    {
        Notification::fake();
        config(['security.captcha.enabled' => false]);

        $user = $this->makeMfaUser('admin3@coc.edu.ph');
        $ticket = app(MfaService::class)->issueChallengeTicket($user);

        $this->postJson('/api/login/mfa/email-code', ['mfa_ticket' => $ticket])->assertOk();

        $this->postJson('/api/login/mfa', [
            'mfa_ticket' => $ticket,
            'code' => '000000',
            'device_name' => 'test',
        ])->assertStatus(422);
    }
}
