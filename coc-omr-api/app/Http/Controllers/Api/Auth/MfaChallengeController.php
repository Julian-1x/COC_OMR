<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\AuthEventLogger;
use App\Services\Auth\MfaService;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class MfaChallengeController extends Controller
{
    public function __construct(
        private readonly MfaService $mfa,
        private readonly AuthEventLogger $events,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'mfa_ticket' => ['required', 'string', 'max:128'],
            'code' => ['required', 'string', 'max:32'],
            'device_name' => ['nullable', 'string', 'max:255'],
        ]);

        $userId = $this->mfa->userIdForTicket($validated['mfa_ticket']);
        if ($userId === null) {
            throw ValidationException::withMessages([
                'mfa_ticket' => ['This sign-in step expired. Go back and enter your password again.'],
            ]);
        }

        /** @var User|null $user */
        $user = User::query()->with('teacherProfile')->find($userId);
        if ($user === null) {
            $this->mfa->forgetTicket($validated['mfa_ticket']);
            throw ValidationException::withMessages([
                'mfa_ticket' => ['This sign-in step expired. Go back and enter your password again.'],
            ]);
        }

        $this->mfa->refreshTicket($validated['mfa_ticket']);

        if (! $this->mfa->verifyCodeOrRecovery($user, $validated['code'])) {
            $this->events->record('mfa_failed', $user->email, $user, $request);

            throw ValidationException::withMessages([
                'code' => ['That code did not match. Try the latest 6-digit code from your authenticator app.'],
            ]);
        }

        $this->mfa->forgetTicket($validated['mfa_ticket']);
        $this->events->record('mfa_success', $user->email, $user, $request);

        $user->loadMissing('teacherProfile');
        $status = $user->teacherProfile?->access_status ?? CocSchool::ACCESS_PENDING;
        if ($status === CocSchool::ACCESS_REVOKED || ! ($user->teacherProfile?->isApproved() ?? false)) {
            $message = $status === CocSchool::ACCESS_REVOKED
                ? 'This account was revoked by your school admin. Contact your COC admin if you need access again.'
                : 'Your account is waiting for school admin approval. Ask your COC admin to approve you before signing in.';

            throw ValidationException::withMessages([
                'email' => [$message],
            ]);
        }

        $token = $user->createToken($validated['device_name'] ?? 'mobile')->plainTextToken;

        return response()->json([
            'user' => RegisterController::userPayload($user),
            'token' => $token,
            'token_type' => 'Bearer',
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);
    }
}
