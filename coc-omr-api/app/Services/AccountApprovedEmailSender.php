<?php

namespace App\Services;

use App\Models\User;
use App\Notifications\AccountApprovedNotification;
use Illuminate\Support\Facades\Log;

class AccountApprovedEmailSender
{
    /**
     * Tell a teacher their school admin approved them.
     *
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
                Log::warning('account_approved_brevo_api_failed', [
                    'user_id' => $user->id,
                    'email' => $user->email,
                    'error' => $lastError,
                ]);
            }
        }

        try {
            $user->notify(new AccountApprovedNotification);

            return ['ok' => true];
        } catch (\Throwable $exception) {
            $smtpError = $exception->getMessage();
            Log::error('account_approved_email_failed', [
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

    private static function sendViaBrevoApi(User $user): void
    {
        $frontend = rtrim((string) config('app.frontend_url'), '/');
        $loginUrl = $frontend !== '' ? $frontend.'/login' : 'https://omrweb.vercel.app/login';
        $name = e((string) ($user->name ?: 'Teacher'));
        $email = e((string) $user->email);

        $html = <<<HTML
<p>Hi {$name},</p>
<p>Good news — your COC OMR teacher account (<strong>{$email}</strong>) has been <strong>approved</strong> by your school admin.</p>
<p>You can sign in now with the same email and password:</p>
<ul>
<li><a href="{$loginUrl}"><strong>Sign in on the web portal</strong></a></li>
<li>Or open the <strong>COC OMR</strong> phone app to scan answer sheets</li>
</ul>
<p>If you did not request a COC OMR account, you can ignore this email.</p>
HTML;

        $text = "Hi {$user->name},\n\n"
            ."Your COC OMR teacher account ({$user->email}) has been approved.\n\n"
            ."Sign in on the web: {$loginUrl}\n"
            ."Or open the COC OMR phone app.\n";

        BrevoMailService::sendTransactional(
            (string) $user->email,
            "You're approved — sign in to COC OMR",
            $html,
            $text,
        );
    }
}
