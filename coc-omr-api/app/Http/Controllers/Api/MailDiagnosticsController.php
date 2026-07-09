<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

class MailDiagnosticsController extends Controller
{
    /**
     * Safe mail config check (no secrets). Use when Render Shell is unavailable.
     */
    public function config(): JsonResponse
    {
        $mailer = (string) config('mail.default');
        $username = (string) config('mail.mailers.smtp.username');
        $from = (string) config('mail.from.address');

        $issues = [];
        if ($mailer !== 'smtp') {
            $issues[] = 'MAIL_MAILER must be smtp on production (currently: '.$mailer.').';
        }
        if ($username === '') {
            $issues[] = 'MAIL_USERNAME is missing.';
        }
        if (! config('mail.mailers.smtp.password')) {
            $issues[] = 'MAIL_PASSWORD is missing.';
        }
        if ($from === '' || str_contains($from, '@smtp-brevo.com')) {
            $issues[] = 'MAIL_FROM_ADDRESS must be a verified Brevo sender (not @smtp-brevo.com).';
        }

        return response()->json([
            'mailer' => $mailer,
            'host' => config('mail.mailers.smtp.host'),
            'port' => config('mail.mailers.smtp.port'),
            'encryption' => config('mail.mailers.smtp.encryption'),
            'username_set' => $username !== '',
            'password_set' => (bool) config('mail.mailers.smtp.password'),
            'from_address' => $from !== '' ? $from : null,
            'auto_verify_email' => (bool) config('app.auto_verify_email'),
            'ok' => $issues === [],
            'issues' => $issues,
        ]);
    }

    /**
     * Send one test email. Requires MAIL_TEST_SECRET on the server (set on Render).
     * POST /api/health/mail-test  { "secret": "...", "email": "you@gmail.com" }
     */
    public function sendTest(Request $request): JsonResponse
    {
        $expected = (string) config('app.mail_test_secret');
        if ($expected === '') {
            return response()->json([
                'message' => 'Mail test is not enabled. Set MAIL_TEST_SECRET on Render, redeploy, then try again.',
            ], 503);
        }

        $request->validate([
            'secret' => ['required', 'string'],
            'email' => ['required', 'email'],
        ]);

        if (! hash_equals($expected, $request->string('secret')->toString())) {
            return response()->json(['message' => 'Invalid secret.'], 403);
        }

        $email = strtolower($request->string('email')->toString());

        try {
            Mail::raw(
                'COC OMR mail test — if you received this, Brevo is working.',
                static function ($message) use ($email): void {
                    $message->to($email)->subject('COC OMR mail test');
                },
            );
        } catch (\Throwable $exception) {
            Log::error('mail_test_failed', ['email' => $email, 'error' => $exception->getMessage()]);

            return response()->json([
                'message' => 'Send failed.',
                'error' => $exception->getMessage(),
            ], 500);
        }

        return response()->json([
            'message' => 'Test email handed off to mail. Check Brevo logs and the inbox (including spam).',
            'email' => $email,
        ]);
    }
}
