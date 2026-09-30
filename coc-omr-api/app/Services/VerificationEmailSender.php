<?php

namespace App\Services;

use App\Models\User;
use App\Notifications\VerifyEmailNotification;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\URL;

class VerificationEmailSender
{
    /**
     * Send a verify email with only one link: phone app OR web — never both.
     *
     * @param  'mobile'|'web'|null  $preferredPlatform  Null → use user's signup_client.
     * @return array{ok: bool, error?: string}
     */
    public static function send(User $user, ?string $preferredPlatform = null): array
    {
        $preferredPlatform = self::normalizePlatform(
            $preferredPlatform ?? (string) ($user->signup_client ?? 'web'),
        );
        $apiKey = trim((string) config('services.brevo.api_key'));
        $lastError = null;

        if ($apiKey !== '') {
            try {
                self::sendViaBrevoApi($user, $preferredPlatform);

                return ['ok' => true];
            } catch (\Throwable $exception) {
                $lastError = $exception->getMessage();
                Log::warning('verification_email_brevo_api_failed', [
                    'user_id' => $user->id,
                    'email' => $user->email,
                    'error' => $lastError,
                ]);
            }
        }

        try {
            $user->notify(new VerifyEmailNotification($preferredPlatform));

            return ['ok' => true];
        } catch (\Throwable $exception) {
            $smtpError = $exception->getMessage();
            $message = $lastError !== null
                ? 'Brevo API failed, then SMTP failed.'
                : $smtpError;

            Log::error('verification_email_failed', [
                'user_id' => $user->id,
                'email' => $user->email,
                'brevo_api_error' => $lastError,
                'smtp_error' => $smtpError,
            ]);
            error_log('verification_email_failed: '.$message);

            return [
                'ok' => false,
                'error' => self::publicHint($lastError ?? $smtpError),
            ];
        }
    }

    public static function publicHint(string $technical): string
    {
        $lower = strtolower($technical);
        if (str_contains($lower, 'brevo_api_key is not configured')) {
            return 'Server is missing BREVO_API_KEY on Render.';
        }
        if (str_contains($lower, '401') || str_contains($lower, 'unauthorized')) {
            return 'Brevo API key is invalid. Create a new key under Brevo → API Keys.';
        }
        if (str_contains($lower, 'sender') || str_contains($lower, 'from')) {
            return 'Brevo rejected the sender address. Use alex.balaba.coc@phinmaed.com as MAIL_FROM_ADDRESS.';
        }
        if (str_contains($lower, 'mail_from_address')) {
            return 'MAIL_FROM_ADDRESS is missing on Render.';
        }

        return 'Email could not be sent. Check Brevo API key and sender on Render.';
    }

    public static function normalizePlatform(string $platform): string
    {
        return strtolower(trim($platform)) === 'mobile' ? 'mobile' : 'web';
    }

    private static function sendViaBrevoApi(User $user, string $preferredPlatform): void
    {
        $url = self::verificationUrl($user, $preferredPlatform);
        $email = e($user->getEmailForVerification());

        if ($preferredPlatform === 'mobile') {
            $html = <<<HTML
<p>You are receiving this email because we received a registration request for your COC OMR account.</p>
<p>This link confirms: <strong>{$email}</strong></p>
<p>You signed up in the <strong>phone app</strong>. Tap below to finish inside COC OMR.</p>
<p><a href="{$url}"><strong>Verify in COC OMR app</strong></a></p>
<p>This link expires in 60 minutes. If you did not request this, you can ignore this email.</p>
HTML;
            $text = "Verify your COC OMR email ({$user->getEmailForVerification()})\n\n"
                ."You signed up in the phone app. Open this link on your phone:\n{$url}\n";
        } else {
            $html = <<<HTML
<p>You are receiving this email because we received a registration request for your COC OMR account.</p>
<p>This link confirms: <strong>{$email}</strong></p>
<p>You signed up on the <strong>web</strong>. Tap below to confirm in your browser.</p>
<p><a href="{$url}"><strong>Verify email</strong></a></p>
<p>Leave the sign-in page open — it can continue after you verify.</p>
<p>This link expires in 60 minutes. If you did not request this, you can ignore this email.</p>
HTML;
            $text = "Verify your COC OMR email ({$user->getEmailForVerification()})\n\n{$url}\n";
        }

        BrevoMailService::sendTransactional(
            $user->getEmailForVerification(),
            'Verify your COC OMR email',
            $html,
            $text,
        );
    }

    public static function verificationUrl(User $user, string $platform): string
    {
        return URL::temporarySignedRoute(
            'verification.verify',
            Carbon::now()->addMinutes(Config::get('auth.verification.expire', 60)),
            [
                'id' => $user->getKey(),
                'hash' => sha1($user->getEmailForVerification()),
                'platform' => self::normalizePlatform($platform),
            ],
        );
    }
}
