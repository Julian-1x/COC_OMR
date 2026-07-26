<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

class RegisterController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'password' => ['required', 'confirmed', Password::defaults()],
            'full_name' => ['required', 'string', 'max:255'],
            // Accepted for backward compatibility with older clients; ignored.
            'school' => ['nullable', 'string', 'max:255'],
        ]);

        $email = strtolower($validated['email']);
        $existing = User::query()->where('email', $email)->first();

        if ($existing?->hasVerifiedEmail()) {
            throw ValidationException::withMessages([
                'email' => ['An account with this email already exists. Use Login instead.'],
            ]);
        }

        if ($existing !== null) {
            return $this->finishRegistration(
                $this->updateUnverifiedUser($existing, $validated),
                resumed: true,
            );
        }

        $user = User::query()->create([
            'name' => $validated['full_name'],
            'email' => $email,
            'password' => Hash::make($validated['password']),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => $validated['full_name'],
            'school_name' => CocSchool::NAME,
            'role' => 'teacher',
            'is_active' => false,
            'access_status' => CocSchool::ACCESS_PENDING,
        ]);

        return $this->finishRegistration($user, resumed: false);
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function updateUnverifiedUser(User $user, array $validated): User
    {
        $user->update([
            'name' => $validated['full_name'],
            'password' => Hash::make($validated['password']),
        ]);

        TeacherProfile::query()->updateOrCreate(
            ['id' => $user->id],
            [
                'full_name' => $validated['full_name'],
                'school_name' => CocSchool::NAME,
                'role' => 'teacher',
                'is_active' => false,
                'access_status' => CocSchool::ACCESS_PENDING,
            ],
        );

        return $user->fresh(['teacherProfile']) ?? $user;
    }

    private function finishRegistration(User $user, bool $resumed): JsonResponse
    {
        $verificationEmailSent = true;
        if (config('app.auto_verify_email')) {
            $user->markEmailAsVerified();
        } else {
            $verificationEmailSent = $this->sendVerificationEmail($user);
        }

        $user->loadMissing('teacherProfile');
        $approved = $user->isAccessApproved();

        $payload = [
            'user' => $this->userPayload($user),
            'token_type' => 'Bearer',
            'resumed_unverified_signup' => $resumed,
            'access_status' => $user->teacherProfile?->access_status ?? CocSchool::ACCESS_PENDING,
        ];

        if ($user->hasVerifiedEmail() && $approved) {
            $payload['token'] = $user->createToken('mobile')->plainTextToken;
        } elseif ($user->hasVerifiedEmail() && ! $approved) {
            $payload['message'] = 'Your email is confirmed. Your account is waiting for school admin approval before you can use the app or web dashboard.';
            $payload['access_pending'] = true;
        } else {
            $payload['message'] = $verificationEmailSent
                ? ($resumed
                    ? 'This email was not confirmed yet. We sent a new confirmation link — check your inbox and spam folder.'
                    : 'Check your email to confirm your account before signing in.')
                : 'Account saved, but we could not send the confirmation email yet. Use Resend confirmation or try again in a few minutes.';
        }

        return response()->json($payload, $resumed ? 200 : 201);
    }

    private function sendVerificationEmail(User $user): bool
    {
        $result = \App\Services\VerificationEmailSender::send($user);

        return $result['ok'];
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
