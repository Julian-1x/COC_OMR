<?php

namespace App\Services;

use App\Models\User;
use App\Notifications\ResetPasswordNotification;
use Illuminate\Support\Facades\Log;

class PasswordResetEmailSender
{
    /**
     * @return array{ok: bool, error?: string}
     */
    public static function send(User $user, string $token): array
    {
        $apiKey = trim((string) config('services.brevo.api_key'));
        $lastError = null;

        if ($apiKey !== '') {
            try {
                self::sendViaBrevoApi($user, $token);

                return ['ok' => true];
            } catch (\Throwable $exception) {
                $lastError = $exception->getMessage();
                Log::warning('password_reset_brevo_api_failed', [
                    'user_id' => $user->id,
                    'email' => $user->email,
                    'error' => $lastError,
                ]);
            }
        }

        try {
            $user->notify(new ResetPasswordNotification($token));

            return ['ok' => true];
        } catch (\Throwable $exception) {
            $smtpError = $exception->getMessage();
            Log::error('password_reset_email_failed', [
                'user_id' => $user->id,
                'email' => $user->email,
                'brevo_api_error' => $lastError,
                'smtp_error' => $smtpError,
            ]);

            return [
                'ok' => false,
                'error' => VerificationEmailSender::publicHint($lastError ?? $smtpError),
            ];
        }
    }

    public static function resetUrl(User $user, string $token): string
    {
        $frontend = rtrim((string) config('app.frontend_url'), '/');

        return $frontend.'/auth/reset-password?'.http_build_query([
            'token' => $token,
            'email' => $user->getEmailForPasswordReset(),
        ]);
    }

    private static function sendViaBrevoApi(User $user, string $token): void
    {
        $frontend = rtrim((string) config('app.frontend_url'), '/');
        if ($frontend === '' || str_contains($frontend, 'localhost')) {
            throw new \RuntimeException('FRONTEND_URL is not configured on the server.');
        }

        $url = self::resetUrl($user, $token);
        $expire = (int) config('auth.passwords.'.config('auth.defaults.passwords').'.expire', 60);

        $html = <<<HTML
<p>You are receiving this email because we received a password reset request for your COC OMR account.</p>
<p><a href="{$url}"><strong>Reset password</strong></a></p>
<p>This link expires in {$expire} minutes. If you did not request a reset, you can ignore this email.</p>
HTML;

        $text = "Reset your COC OMR password\n\n{$url}\n\nThis link expires in {$expire} minutes.";

        BrevoMailService::sendTransactional(
            $user->getEmailForPasswordReset(),
            'Reset your COC OMR password',
            $html,
            $text,
        );
    }
}
