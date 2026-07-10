<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Password;
use Illuminate\Validation\ValidationException;

class ForgotPasswordController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email'],
        ]);

        try {
            $status = Password::sendResetLink([
                'email' => strtolower($request->string('email')->toString()),
            ]);
        } catch (\Throwable $exception) {
            Log::error('forgot_password_failed', [
                'email' => strtolower($request->string('email')->toString()),
                'error' => $exception->getMessage(),
            ]);

            return response()->json([
                'message' => 'We could not send the reset email right now. Try again in a few minutes.',
            ], 503);
        }

        if ($status === Password::RESET_LINK_SENT || $status === Password::INVALID_USER) {
            return response()->json([
                'message' => 'If that email is registered, a reset link is on its way.',
            ]);
        }

        throw ValidationException::withMessages([
                'email' => [__($status)],
        ]);
    }
}
