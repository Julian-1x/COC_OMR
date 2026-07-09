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
    public static function send(User $user): bool
    {
        try {
            if ((string) config('services.brevo.api_key') !== '') {
                self::sendViaBrevoApi($user);
            } else {
                $user->notify(new VerifyEmailNotification);
            }

            return true;
        } catch (\Throwable $exception) {
            $message = $exception->getMessage();
            Log::error('verification_email_failed', [
                'user_id' => $user->id,
                'email' => $user->email,
                'error' => $message,
            ]);
            error_log('verification_email_failed: '.$message);

            return false;
        }
    }

    private static function sendViaBrevoApi(User $user): void
    {
        $webUrl = self::verificationUrl($user, 'web');
        $mobileUrl = self::verificationUrl($user, 'mobile');
        $fromName = e((string) config('mail.from.name', 'COC OMR'));

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
