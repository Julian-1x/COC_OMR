<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\BrevoMailService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class MailDiagnosticsController extends Controller
{
    /**
     * Safe mail config check (no secrets). Use when Render Shell is unavailable.
     */
    public function config(): JsonResponse
    {
        $mailer = (string) config('mail.default');
        $from = (string) config('mail.from.address');
        $brevoKeySet = (string) config('services.brevo.api_key') !== '';
        $appUrl = (string) config('app.url');

        $issues = [];
        if ($from === '' || str_contains($from, '@smtp-brevo.com')) {
            $issues[] = 'MAIL_FROM_ADDRESS must be a verified Brevo sender (e.g. alex.balaba.coc@phinmaed.com).';
        }
        if (! $brevoKeySet && $mailer !== 'smtp') {
            $issues[] = 'Set BREVO_API_KEY (recommended) or MAIL_MAILER=smtp on Render.';
        }
        if ($appUrl === '' || str_contains($appUrl, 'localhost')) {
            $issues[] = 'APP_URL must be https://coc-omr-api.onrender.com on Render.';
        }
        $frontendUrl = (string) config('app.frontend_url');
        if ($frontendUrl === '' || str_contains($frontendUrl, 'localhost')) {
            $issues[] = 'FRONTEND_URL must be https://omrweb.vercel.app on Render.';
        }
        $autoVerify = (bool) config('app.auto_verify_email');
        if ($autoVerify && config('app.env') === 'production') {
            $issues[] = 'AUTO_VERIFY_EMAIL is true — confirmation emails are skipped and fake addresses can register. Set AUTO_VERIFY_EMAIL=false on Render.';
        }

        return response()->json([
            'mailer' => $mailer,
            'brevo_api_key_set' => $brevoKeySet,
            'active_transport' => $brevoKeySet ? 'brevo_api' : 'smtp',
            'from_address' => $from !== '' ? $from : null,
            'app_url' => $appUrl,
            'frontend_url' => $frontendUrl !== '' ? $frontendUrl : null,
            'auto_verify_email' => $autoVerify,
            'ok' => $issues === [],
            'issues' => $issues,
        ]);
    }

    /**
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
            BrevoMailService::sendTransactional(
                $email,
                'COC OMR mail test',
                '<p>COC OMR mail test — if you received this, Brevo is working.</p>',
                'COC OMR mail test — if you received this, Brevo is working.',
            );
        } catch (\Throwable $exception) {
            Log::error('mail_test_failed', ['email' => $email, 'error' => $exception->getMessage()]);

            return response()->json([
                'message' => 'Send failed.',
                'error' => $exception->getMessage(),
            ], 500);
        }

        return response()->json([
            'message' => 'Test email sent via Brevo API. Check Brevo logs and the inbox (including spam).',
            'email' => $email,
        ]);
    }
}
