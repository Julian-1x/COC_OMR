<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use App\Support\PersonName;
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
            'department' => ['required', 'string', 'in:'.implode(',', CocSchool::DEPARTMENTS)],
            // Accepted for backward compatibility with older clients; ignored.
            'school' => ['nullable', 'string', 'max:255'],
        ]);

        $email = strtolower($validated['email']);
        $department = CocSchool::normalizeDepartment($validated['department']);
        $fullName = PersonName::normalize($validated['full_name']);
        if ($fullName === '') {
            throw ValidationException::withMessages([
                'full_name' => ['Enter your full name (first name, then last name).'],
            ]);
        }
        $validated['full_name'] = $fullName;
        $existing = User::query()->where('email', $email)->with('teacherProfile')->first();

        if ($existing?->hasVerifiedEmail()) {
            $status = $existing->teacherProfile?->access_status ?? CocSchool::ACCESS_PENDING;
            $isActive = $existing->teacherProfile?->is_active ?? false;

            if ($status === CocSchool::ACCESS_REVOKED || ($existing->teacherProfile && ! $isActive && $status !== CocSchool::ACCESS_PENDING)) {
                throw ValidationException::withMessages([
                    'email' => ['This account was revoked by your school admin. Contact your COC admin if you need access again.'],
                ]);
            }

            if ($status !== CocSchool::ACCESS_APPROVED || ! $isActive) {
                throw ValidationException::withMessages([
                    'email' => ['Your account is waiting for school admin approval. Ask your COC admin to approve you, then use Login.'],
                ]);
            }

            throw ValidationException::withMessages([
                'email' => ['An account with this email already exists. Use Login instead.'],
            ]);
        }

        if ($existing !== null) {
            return $this->finishRegistration(
                $this->updateUnverifiedUser($existing, $validated, $department),
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
            'department' => $department,
            'role' => 'teacher',
            'is_active' => false,
            'access_status' => CocSchool::ACCESS_PENDING,
        ]);

        return $this->finishRegistration($user, resumed: false);
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function updateUnverifiedUser(User $user, array $validated, string $department): User
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
                'department' => $department,
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
