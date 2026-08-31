<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\MfaService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class MfaEnrollController extends Controller
{
    public function __construct(private readonly MfaService $mfa) {}

    public function setup(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $payload = $this->mfa->beginEnrollment($user);

        return response()->json([
            'secret' => $payload['secret'],
            'otpauth_url' => $payload['otpauth_url'],
            'message' => 'Add this key to Google Authenticator or a similar app, then confirm with a 6-digit code.',
        ]);
    }

    public function confirm(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $validated = $request->validate([
            'code' => ['required', 'string', 'max:32'],
        ]);

        $recoveryCodes = $this->mfa->confirmEnrollment($user, $validated['code']);

        return response()->json([
            'recovery_codes' => $recoveryCodes,
            'message' => 'Two-factor sign-in is on. Store these recovery codes somewhere safe.',
        ]);
    }

    public function disable(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        if ($this->mfa->roleRequiresMfa($user)) {
            throw ValidationException::withMessages([
                'code' => ['School admins must keep two-factor sign-in enabled.'],
            ]);
        }

        $validated = $request->validate([
            'code' => ['required', 'string', 'max:32'],
        ]);

        $this->mfa->disable($user, $validated['code']);

        return response()->json([
            'message' => 'Two-factor sign-in is off for this account.',
        ]);
    }

    /**
     * Begin MFA setup during sign-in (admin accounts).
     */
    public function setupDuringLogin(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'mfa_ticket' => ['required', 'string', 'max:128'],
        ]);

        $userId = $this->mfa->userIdForTicket($validated['mfa_ticket']);
        if ($userId === null) {
            throw ValidationException::withMessages([
                'mfa_ticket' => ['This setup step expired. Sign in with your password again.'],
            ]);
        }

        /** @var User|null $user */
        $user = User::query()->find($userId);
        if ($user === null) {
            throw ValidationException::withMessages([
                'mfa_ticket' => ['This setup step expired. Sign in with your password again.'],
            ]);
        }

        $this->mfa->refreshTicket($validated['mfa_ticket']);

        $payload = $this->mfa->beginEnrollment($user);

        return response()->json([
            'secret' => $payload['secret'],
            'otpauth_url' => $payload['otpauth_url'],
        ]);
    }

    /**
     * Complete mandatory admin enrollment during sign-in (password already verified).
     */
    public function enrollDuringLogin(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'mfa_ticket' => ['required', 'string', 'max:128'],
            'code' => ['required', 'string', 'max:32'],
            'device_name' => ['nullable', 'string', 'max:255'],
        ]);

        $userId = $this->mfa->userIdForTicket($validated['mfa_ticket']);
        if ($userId === null) {
            throw ValidationException::withMessages([
                'mfa_ticket' => ['This setup step expired. Sign in with your password again.'],
            ]);
        }

        /** @var User|null $user */
        $user = User::query()->with('teacherProfile')->find($userId);
        if ($user === null) {
            throw ValidationException::withMessages([
                'mfa_ticket' => ['This setup step expired. Sign in with your password again.'],
            ]);
        }

        $this->mfa->refreshTicket($validated['mfa_ticket']);

        if ($user->two_factor_secret === null) {
            throw ValidationException::withMessages([
                'code' => ['Setup did not finish loading. Wait until the setup key appears, then try again.'],
            ]);
        }

        $recoveryCodes = $this->mfa->confirmEnrollment($user, $validated['code']);
        $this->mfa->forgetTicket($validated['mfa_ticket']);

        $token = $user->createToken($validated['device_name'] ?? 'mobile')->plainTextToken;

        return response()->json([
            'user' => RegisterController::userPayload($user),
            'token' => $token,
            'token_type' => 'Bearer',
            'recovery_codes' => $recoveryCodes,
            'message' => 'Two-factor sign-in is on. Store your recovery codes somewhere safe.',
        ]);
    }
}
