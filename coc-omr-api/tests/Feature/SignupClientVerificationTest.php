<?php

namespace Tests\Feature;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Notifications\VerifyEmailNotification;
use App\Services\VerificationEmailSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class SignupClientVerificationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config([
            'security.captcha.enabled' => false,
            'services.brevo.api_key' => '',
            'app.auto_verify_email' => false,
        ]);
    }

    public function test_mobile_signup_stores_client_and_email_has_only_app_action(): void
    {
        Notification::fake();

        $response = $this->postJson('/api/register', [
            'email' => 'phone.teacher@example.com',
            'password' => 'Password1!',
            'password_confirmation' => 'Password1!',
            'full_name' => 'Phone Teacher',
            'department' => 'COE',
            'client' => 'mobile',
        ]);

        $response->assertCreated();
        $user = User::query()->where('email', 'phone.teacher@example.com')->first();
        $this->assertNotNull($user);
        $this->assertSame('mobile', $user->signup_client);

        Notification::assertSentTo($user, VerifyEmailNotification::class, function (VerifyEmailNotification $mail) use ($user) {
            $message = $mail->toMail($user);
            $this->assertSame('Verify in COC OMR app', $message->actionText);
            $this->assertStringContainsString('platform=mobile', $message->actionUrl);
            $this->assertStringNotContainsString('platform=web', $message->actionUrl);

            return true;
        });
    }

    public function test_web_signup_email_has_only_browser_action(): void
    {
        Notification::fake();

        $response = $this->postJson('/api/register', [
            'email' => 'web.teacher@example.com',
            'password' => 'Password1!',
            'password_confirmation' => 'Password1!',
            'full_name' => 'Web Teacher',
            'department' => 'COE',
            'client' => 'web',
        ]);

        $response->assertCreated();
        $user = User::query()->where('email', 'web.teacher@example.com')->first();
        $this->assertNotNull($user);
        $this->assertSame('web', $user->signup_client);

        Notification::assertSentTo($user, VerifyEmailNotification::class, function (VerifyEmailNotification $mail) use ($user) {
            $message = $mail->toMail($user);
            $this->assertSame('Verify email', $message->actionText);
            $this->assertStringContainsString('platform=web', $message->actionUrl);

            return true;
        });
    }

    public function test_resend_without_client_uses_stored_signup_client(): void
    {
        Notification::fake();

        $user = User::query()->create([
            'name' => 'Stored Mobile',
            'email' => 'stored.mobile@example.com',
            'password' => bcrypt('Password1!'),
            'signup_client' => 'mobile',
        ]);
        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => 'Stored Mobile',
            'school_name' => 'COC',
            'role' => 'teacher',
            'is_active' => false,
        ]);

        $this->postJson('/api/email/resend-verification', [
            'email' => 'stored.mobile@example.com',
        ])->assertOk();

        Notification::assertSentTo($user, VerifyEmailNotification::class, function (VerifyEmailNotification $mail) use ($user) {
            $message = $mail->toMail($user);
            $this->assertSame('Verify in COC OMR app', $message->actionText);

            return true;
        });
    }

    public function test_verification_url_platform_helper(): void
    {
        $user = User::query()->create([
            'name' => 'Url Teacher',
            'email' => 'url.teacher@example.com',
            'password' => bcrypt('Password1!'),
            'signup_client' => 'mobile',
        ]);

        $mobile = VerificationEmailSender::verificationUrl($user, 'mobile');
        $web = VerificationEmailSender::verificationUrl($user, 'web');
        $this->assertStringContainsString('platform=mobile', $mobile);
        $this->assertStringContainsString('platform=web', $web);
    }
}
