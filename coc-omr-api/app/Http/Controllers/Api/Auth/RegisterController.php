<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rules\Password;

class RegisterController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'confirmed', Password::defaults()],
            'full_name' => ['required', 'string', 'max:255'],
            'school' => ['nullable', 'string', 'max:255'],
        ]);

        $user = User::query()->create([
            'name' => $validated['full_name'],
            'email' => strtolower($validated['email']),
            'password' => Hash::make($validated['password']),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => $validated['full_name'],
            'school_name' => $validated['school'] ?? null,
            'role' => 'teacher',
            'is_active' => true,
        ]);

        $verificationEmailSent = true;
        if (config('app.auto_verify_email')) {
            $user->markEmailAsVerified();
        } else {
            $verificationEmailSent = $this->sendVerificationEmail($user);
        }

        $payload = [
            'user' => $this->userPayload($user),
            'token_type' => 'Bearer',
        ];

        if ($user->hasVerifiedEmail()) {
            $payload['token'] = $user->createToken('mobile')->plainTextToken;
        } else {
            $payload['message'] = $verificationEmailSent
                ? 'Check your email to confirm your account before signing in.'
                : 'Account created, but we could not send the confirmation email yet. Use Resend confirmation or try again in a few minutes.';
        }

        return response()->json($payload, 201);
    }

    private function sendVerificationEmail(User $user): bool
    {
        try {
            $user->sendEmailVerificationNotification();

            return true;
        } catch (\Throwable $exception) {
            Log::error('verification_email_failed', [
                'user_id' => $user->id,
                'email' => $user->email,
                'error' => $exception->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * @return array<string, mixed>
     */
    public static function userPayload(User $user): array
    {
        $user->loadMissing('teacherProfile');

        return [
            'id' => $user->id,
            'email' => $user->email,
            'email_verified_at' => $user->email_verified_at,
            'profile' => $user->teacherProfile,
        ];
    }
}
