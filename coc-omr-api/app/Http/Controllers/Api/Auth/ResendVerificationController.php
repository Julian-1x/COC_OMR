<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\VerificationEmailSender;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ResendVerificationController extends Controller
{
    /**
     * Resend email verification without requiring a verified session.
     * Always returns a generic message (does not reveal if email exists).
     * Uses signup_client (phone vs web) so the email only has that platform's link.
     */
    public function __invoke(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email'],
            'client' => ['nullable', 'string', 'in:mobile,web'],
        ]);

        $email = strtolower($request->string('email')->toString());
        $user = User::query()->where('email', $email)->first();

        if ($user !== null && ! $user->hasVerifiedEmail()) {
            $client = $request->filled('client')
                ? VerificationEmailSender::normalizePlatform((string) $request->input('client'))
                : $user->preferredVerifyPlatform();

            if (($user->signup_client ?? null) !== $client) {
                $user->forceFill(['signup_client' => $client])->save();
            }

            $result = VerificationEmailSender::send($user, $client);
            if (! $result['ok']) {
                return response()->json([
                    'message' => $result['error'] ?? 'We could not send the confirmation email.',
                    'email_sent' => false,
                ], 503);
            }
        }

        return response()->json([
            'message' => 'If that email is registered and not yet confirmed, a verification link has been sent.',
            'email_sent' => true,
        ]);
    }
}
