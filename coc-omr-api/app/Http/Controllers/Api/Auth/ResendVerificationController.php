<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class ResendVerificationController extends Controller
{
    /**
     * Resend email verification without requiring a verified session.
     * Always returns a generic message (does not reveal if email exists).
     */
    public function __invoke(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email'],
        ]);

        $email = strtolower($request->string('email')->toString());
        $user = User::query()->where('email', $email)->first();

        if ($user !== null && ! $user->hasVerifiedEmail()) {
            $sent = $this->sendVerificationEmail($user);
            if (! $sent) {
                return response()->json([
                    'message' => 'We could not send the confirmation email. Ask your admin to verify Brevo sender settings on the server.',
                    'email_sent' => false,
                ], 503);
            }
        }

        return response()->json([
            'message' => 'If that email is registered and not yet confirmed, a verification link has been sent.',
            'email_sent' => true,
        ]);
    }

    private function sendVerificationEmail(User $user): bool
    {
        try {
            $user->sendEmailVerificationNotification();

            return true;
        } catch (\Throwable $exception) {
            Log::error('verification_email_resend_failed', [
                'user_id' => $user->id,
                'email' => $user->email,
                'error' => $exception->getMessage(),
            ]);

            return false;
        }
    }
}
