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
     * @return array{ok: bool, error?: string}
     */
    public static function send(User $user): array
    {
        $apiKey = trim((string) config('services.brevo.api_key'));
        $lastError = null;

        if ($apiKey !== '') {
            try {
                self::sendViaBrevoApi($user);

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
            $user->notify(new VerifyEmailNotification);

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

    private static function sendViaBrevoApi(User $user): void
    {
        $webUrl = self::verificationUrl($user, 'web');
        $mobileUrl = self::verificationUrl($user, 'mobile');

        $html = <<<HTML
<p>You are receiving this email because we received a registration request for your COC OMR account.</p>
<p><a href="{$webUrl}"><strong>Verify email (web)</strong></a></p>
<p>On your phone? Open this link:</p>
<p><a href="{$mobileUrl}">{$mobileUrl}</a></p>
<p>This link expires in 60 minutes. If you did not request this, you can ignore this email.</p>
HTML;

        $text = "Verify your COC OMR email\n\nWeb: {$webUrl}\n\nPhone: {$mobileUrl}\n";

        BrevoMailService::sendTransactional(
            $user->getEmailForVerification(),
            'Verify your COC OMR email',
            $html,
            $text,
        );
    }

    private static function verificationUrl(User $user, string $platform): string
    {
        $base = URL::temporarySignedRoute(
            'verification.verify',
            Carbon::now()->addMinutes(Config::get('auth.verification.expire', 60)),
            [
                'id' => $user->getKey(),
                'hash' => sha1($user->getEmailForVerification()),
            ],
        );

        return $base.(str_contains($base, '?') ? '&' : '?').'platform='.$platform;
    }
}
