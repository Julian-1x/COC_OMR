<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use App\Support\PersonName;
use App\Services\TeacherApprovalBootstrap;
use App\Services\Auth\AuthEventLogger;
use App\Services\Auth\CaptchaVerifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

class RegisterController extends Controller
{
    public function __construct(
        private readonly CaptchaVerifier $captcha,
        private readonly AuthEventLogger $events,
        private readonly \App\Services\Auth\MfaService $mfa,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'password' => ['required', 'confirmed', Password::defaults()],
            'full_name' => ['required', 'string', 'max:255'],
            'department' => ['required', 'string', 'in:'.implode(',', CocSchool::DEPARTMENTS)],
            // Accepted for backward compatibility with older clients; ignored.
            'school' => ['nullable', 'string', 'max:255'],
            'captcha_token' => ['nullable', 'string'],
            // phone app → mobile deep-link as primary verify button; web → browser link.
            'client' => ['nullable', 'string', 'in:mobile,web'],
        ]);

        $this->captcha->assertValid($validated['captcha_token'] ?? null, $request);

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

        $client = \App\Services\VerificationEmailSender::normalizePlatform(
            (string) ($validated['client'] ?? 'web'),
        );

        try {
            if ($existing !== null) {
                return $this->finishRegistration(
                    $this->updateUnverifiedUser($existing, $validated, $department),
                    resumed: true,
                    client: $client,
                );
            }

            $userAttrs = [
                'name' => $validated['full_name'],
                'email' => $email,
                'password' => Hash::make($validated['password']),
            ];
            if (Schema::hasColumn('users', 'signup_client')) {
                $userAttrs['signup_client'] = $client;
            }

            $user = User::query()->create($userAttrs);

            TeacherProfile::query()->create([
                'id' => $user->id,
                'full_name' => $validated['full_name'],
                'school_name' => CocSchool::NAME,
                'department' => $department,
                'role' => 'teacher',
                'is_active' => false,
                'access_status' => CocSchool::ACCESS_PENDING,
            ]);

            return $this->finishRegistration($user, resumed: false, client: $client);
        } catch (ValidationException $exception) {
            throw $exception;
        } catch (\Throwable $exception) {
            Log::error('register_failed', [
                'email' => $email,
                'error' => $exception->getMessage(),
            ]);

            return response()->json([
                'message' => 'Could not create your account just now. Wait a few seconds, refresh the security check, then try Create Account again.',
            ], 503);
        }
    }

    /**
     * @param  array<string, mixed>  $validated
     */
    private function updateUnverifiedUser(User $user, array $validated, string $department): User
    {
        $attrs = [
            'name' => $validated['full_name'],
            'password' => Hash::make($validated['password']),
        ];
        if (Schema::hasColumn('users', 'signup_client')) {
            $attrs['signup_client'] = \App\Services\VerificationEmailSender::normalizePlatform(
                (string) ($validated['client'] ?? $user->signup_client ?? 'web'),
            );
        }
        $user->update($attrs);

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

    private function finishRegistration(User $user, bool $resumed, string $client = 'web'): JsonResponse
    {
        // Never write signup_client unless the production column exists
        // (missing migration must not break register with a 500/503).
        if (
            Schema::hasColumn('users', 'signup_client')
            && ($user->signup_client ?? null) !== $client
        ) {
            $user->forceFill(['signup_client' => $client])->save();
        }

        $this->events->record(
            $resumed ? 'register_resumed' : 'register_created',
            $user->email,
            $user,
            request(),
        );

        $verificationEmailSent = true;
        if (config('app.auto_verify_email')) {
            if (config('app.env') === 'production') {
                \Illuminate\Support\Facades\Log::warning('auto_verify_email_enabled_in_production', [
                    'user_id' => $user->id,
                    'email' => $user->email,
                ]);
            }
            $user->markEmailAsVerified();
        } else {
            $verificationEmailSent = $this->sendVerificationEmail($user, $client);
        }

        $user->loadMissing('teacherProfile');
        TeacherApprovalBootstrap::approveIfListed($user);
        $user->load('teacherProfile');
        $approved = $user->isAccessApproved();

        $payload = [
            'user' => $this->userPayload($user),
            'token_type' => 'Bearer',
            'resumed_unverified_signup' => $resumed,
            'access_status' => $user->teacherProfile?->access_status ?? CocSchool::ACCESS_PENDING,
            'email_sent' => $user->hasVerifiedEmail() ? null : $verificationEmailSent,
        ];

        if ($user->hasVerifiedEmail() && $approved) {
            if ($this->mfa->mustEnroll($user)) {
                $ticket = $this->mfa->issueChallengeTicket($user);
                $payload['mfa_enrollment_required'] = true;
                $payload['mfa_ticket'] = $ticket;
                $payload['message'] = 'Set up two-factor authentication before continuing.';
            } else {
                $payload['token'] = $user->createToken('mobile')->plainTextToken;
            }
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

    private function sendVerificationEmail(User $user, string $client = 'web'): bool
    {
        $result = \App\Services\VerificationEmailSender::send($user, $client);

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
