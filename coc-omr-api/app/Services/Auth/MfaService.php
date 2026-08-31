<?php

namespace App\Services\Auth;

use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class MfaService
{
    public function __construct(
        private readonly TotpService $totp,
        private readonly AuthEventLogger $events,
    ) {}

    public function mustEnroll(User $user): bool
    {
        if ($user->two_factor_confirmed_at !== null) {
            return false;
        }

        return $this->roleRequiresMfa($user);
    }

    public function hasConfirmedMfa(User $user): bool
    {
        return $user->two_factor_confirmed_at !== null
            && is_string($user->two_factor_secret)
            && $user->two_factor_secret !== '';
    }

    public function roleRequiresMfa(User $user): bool
    {
        $role = $user->teacherProfile?->role;
        $required = config('security.mfa.required_roles', []);

        return is_string($role) && in_array($role, $required, true);
    }

    /**
     * @return array{secret: string, otpauth_url: string}
     */
    public function beginEnrollment(User $user): array
    {
        $existing = $this->decryptSecret($user);
        if ($existing !== null && $user->two_factor_confirmed_at === null) {
            return [
                'secret' => $existing,
                'otpauth_url' => $this->totp->provisioningUri($user->email, $existing),
            ];
        }

        $secret = $this->totp->generateSecret();

        $user->forceFill([
            'two_factor_secret' => encrypt($secret),
            'two_factor_confirmed_at' => null,
            'two_factor_recovery_codes' => null,
        ])->save();

        return [
            'secret' => $secret,
            'otpauth_url' => $this->totp->provisioningUri($user->email, $secret),
        ];
    }

    /**
     * @return list<string>
     */
    public function confirmEnrollment(User $user, string $code): array
    {
        $secret = $this->decryptSecret($user);
        // Wider window during first-time setup — slow hosts and clock skew are common.
        if ($secret === null || ! $this->totp->verify($secret, $code, 3)) {
            throw ValidationException::withMessages([
                'code' => ['That code did not match. Wait for a fresh 6-digit code in your authenticator app, then try again.'],
            ]);
        }

        $recoveryCodes = $this->generateRecoveryCodes();
        $user->forceFill([
            'two_factor_confirmed_at' => now(),
            'two_factor_recovery_codes' => encrypt(json_encode($recoveryCodes, JSON_THROW_ON_ERROR)),
        ])->save();

        $this->events->record('mfa_enrolled', $user->email, $user);

        return $recoveryCodes;
    }

    public function disable(User $user, string $code): void
    {
        if (! $this->verifyCodeOrRecovery($user, $code)) {
            throw ValidationException::withMessages([
                'code' => ['Enter a valid authenticator or recovery code to turn off two-factor sign-in.'],
            ]);
        }

        $user->forceFill([
            'two_factor_secret' => null,
            'two_factor_recovery_codes' => null,
            'two_factor_confirmed_at' => null,
        ])->save();

        $this->events->record('mfa_disabled', $user->email, $user);
    }

    public function issueChallengeTicket(User $user): string
    {
        $ticket = Str::random(64);
        $this->storeTicket($ticket, $user->id);

        return $ticket;
    }

    public function refreshTicket(string $ticket): bool
    {
        $userId = $this->userIdForTicket($ticket);
        if ($userId === null) {
            return false;
        }

        $this->storeTicket($ticket, $userId);

        return true;
    }

    public function userIdForTicket(string $ticket): ?string
    {
        return Cache::get($this->ticketKey($ticket));
    }

    public function forgetTicket(string $ticket): void
    {
        Cache::forget($this->ticketKey($ticket));
    }

    public function verifyCodeOrRecovery(User $user, string $code): bool
    {
        $secret = $this->decryptSecret($user);
        if ($secret !== null && $this->totp->verify($secret, $code, 3)) {
            return true;
        }

        return $this->consumeRecoveryCode($user, $code);
    }

    private function consumeRecoveryCode(User $user, string $code): bool
    {
        $raw = $user->two_factor_recovery_codes;
        if (! is_string($raw) || $raw === '') {
            return false;
        }

        try {
            /** @var list<string> $codes */
            $codes = json_decode(decrypt($raw), true, 512, JSON_THROW_ON_ERROR);
        } catch (\Throwable) {
            return false;
        }

        $normalized = strtoupper(preg_replace('/\s+/', '', $code) ?? '');
        foreach ($codes as $index => $stored) {
            if (hash_equals(strtoupper($stored), $normalized)) {
                array_splice($codes, $index, 1);
                $user->forceFill([
                    'two_factor_recovery_codes' => encrypt(json_encode(array_values($codes), JSON_THROW_ON_ERROR)),
                ])->save();

                return true;
            }
        }

        return false;
    }

    private function decryptSecret(User $user): ?string
    {
        if (! is_string($user->two_factor_secret) || $user->two_factor_secret === '') {
            return null;
        }

        try {
            return decrypt($user->two_factor_secret);
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * @return list<string>
     */
    private function generateRecoveryCodes(int $count = 8): array
    {
        $codes = [];
        for ($i = 0; $i < $count; $i++) {
            $codes[] = strtoupper(Str::random(4).'-'.Str::random(4));
        }

        return $codes;
    }

    private function storeTicket(string $ticket, string $userId): void
    {
        $ttl = (int) config('security.mfa.challenge_ttl_minutes', 15);
        Cache::put($this->ticketKey($ticket), $userId, now()->addMinutes($ttl));
    }

    private function ticketKey(string $ticket): string
    {
        return 'mfa_ticket:'.$ticket;
    }
}
