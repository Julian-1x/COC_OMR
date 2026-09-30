<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\AuthEventLogger;
use App\Services\Auth\MfaService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class MfaEmailCodeController extends Controller
{
    public function __construct(
        private readonly MfaService $mfa,
        private readonly AuthEventLogger $events,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'mfa_ticket' => ['required', 'string', 'max:128'],
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

        if (! $this->mfa->hasConfirmedMfa($user)) {
            throw ValidationException::withMessages([
                'mfa_ticket' => ['Set up your authenticator app first. Email codes are only a backup after that.'],
            ]);
        }

        $this->mfa->refreshTicket($validated['mfa_ticket']);
        $result = $this->mfa->sendEmailChallengeCode($user, $validated['mfa_ticket']);

        $this->events->record('mfa_email_code_sent', $user->email, $user, $request);

        return response()->json([
            'ok' => true,
            'message' => $result['message'],
            'email_hint' => $result['email_hint'],
            'resend_after_seconds' => $result['resend_after_seconds'],
        ]);
    }
}
