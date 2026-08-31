<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Api\Auth\RegisterController as AuthRegisterController;
use App\Models\User;
use App\Services\AdminBootstrap;
use App\Services\Auth\CaptchaVerifier;
use App\Services\Auth\LoginSecurityService;
use App\Services\Auth\MfaService;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function __construct(
        private readonly LoginSecurityService $security,
        private readonly CaptchaVerifier $captcha,
        private readonly MfaService $mfa,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:255'],
            'captcha_token' => ['nullable', 'string'],
        ]);

        $email = strtolower($credentials['email']);

        $this->security->assertNotLocked($email, $request);

        if ($this->security->requiresCaptcha($email, $request)) {
            if ($credentials['captcha_token'] === null) {
                return response()->json(
                    $this->security->captchaRequiredPayload($email, $request),
                    422,
                );
            }
            $this->captcha->assertValid($credentials['captcha_token'], $request);
        }

        if (! Auth::attempt([
            'email' => $email,
            'password' => $credentials['password'],
        ])) {
            $existing = User::query()->where('email', $email)->first();
            $this->security->recordFailure($email, $request, $existing);

            $payload = ['email' => ['These credentials do not match our records.']];
            if ($this->security->requiresCaptcha($email, $request) && $this->captcha->isEnabled()) {
                return response()->json(array_merge(
                    ['errors' => $payload, 'message' => 'These credentials do not match our records.'],
                    $this->security->captchaRequiredPayload($email, $request),
                ), 422);
            }

            throw ValidationException::withMessages($payload);
        }

        /** @var User $user */
        $user = Auth::user();
        $user->loadMissing('teacherProfile');

        if (AdminBootstrap::promoteIfListed($user)) {
            $user->load('teacherProfile');
        }

        $profile = $user->teacherProfile;
        $accessStatus = $profile?->access_status ?? CocSchool::ACCESS_PENDING;

        if ($accessStatus === CocSchool::ACCESS_REVOKED || ($profile && ! $profile->is_active && $accessStatus !== CocSchool::ACCESS_PENDING)) {
            Auth::logout();
            $this->security->recordFailure($email, $request, $user);

            throw ValidationException::withMessages([
                'email' => ['This account was revoked by your school admin. Contact your COC admin if you need access again.'],
            ]);
        }

        if (! config('app.auto_verify_email') && ! $user->hasVerifiedEmail()) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['This email has not been confirmed yet. Open the confirmation email, then sign in again.'],
            ]);
        }

        if ($accessStatus !== CocSchool::ACCESS_APPROVED || ! ($profile?->is_active ?? false)) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['Your account is waiting for school admin approval. Ask your COC admin to approve you before signing in.'],
            ]);
        }

        Auth::logout();

        $this->security->recordSuccess($user, $request);

        if ($this->mfa->mustEnroll($user)) {
            $ticket = $this->mfa->issueChallengeTicket($user);

            return response()->json([
                'mfa_enrollment_required' => true,
                'mfa_ticket' => $ticket,
                'message' => 'Set up two-factor authentication before continuing.',
                'user' => AuthRegisterController::userPayload($user),
            ]);
        }

        if ($this->mfa->hasConfirmedMfa($user)) {
            $ticket = $this->mfa->issueChallengeTicket($user);

            return response()->json([
                'mfa_required' => true,
                'mfa_ticket' => $ticket,
                'message' => 'Enter the 6-digit code from your authenticator app.',
            ]);
        }

        return $this->tokenResponse($user, $credentials['device_name'] ?? 'mobile');
    }

    private function tokenResponse(User $user, string $deviceName): JsonResponse
    {
        $token = $user->createToken($deviceName)->plainTextToken;

        return response()->json([
            'user' => AuthRegisterController::userPayload($user),
            'token' => $token,
            'token_type' => 'Bearer',
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);
    }
}
