<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:255'],
        ]);

        if (! Auth::attempt([
            'email' => strtolower($credentials['email']),
            'password' => $credentials['password'],
        ])) {
            throw ValidationException::withMessages([
                'email' => ['These credentials do not match our records.'],
            ]);
        }

        /** @var \App\Models\User $user */
        $user = Auth::user();

        if ($user->teacherProfile && ! $user->teacherProfile->is_active) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['This account is inactive. Contact your school IT lead.'],
            ]);
        }

        if (! config('app.auto_verify_email') && ! $user->hasVerifiedEmail()) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['This email has not been confirmed yet. Open the confirmation email, then sign in again.'],
            ]);
        }

        $deviceName = $credentials['device_name'] ?? 'mobile';
        $token = $user->createToken($deviceName)->plainTextToken;

        return response()->json([
            'user' => RegisterController::userPayload($user),
            'token' => $token,
            'token_type' => 'Bearer',
        ]);
    }
}
