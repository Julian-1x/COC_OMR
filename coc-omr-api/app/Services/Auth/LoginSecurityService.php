<?php

namespace App\Services\Auth;

use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class LoginSecurityService
{
    public function __construct(
        private readonly AuthEventLogger $events,
        private readonly CaptchaVerifier $captcha,
    ) {}

    public function cacheKey(string $email, Request $request): string
    {
        return sha1(strtolower(trim($email)).'|'.($request->ip() ?? 'unknown'));
    }

    public function recentFailureCount(string $email, Request $request): int
    {
        return (int) Cache::get($this->failuresCacheKey($email, $request), 0);
    }

    public function requiresCaptcha(string $email, Request $request): bool
    {
        if (! $this->captcha->isEnabled()) {
            return false;
        }

        $threshold = (int) config('security.login.captcha_after_failures', 3);

        return $this->recentFailureCount($email, $request) >= $threshold;
    }

    /**
     * @throws ValidationException
     */
    public function assertCaptchaIfRequired(?string $token, string $email, Request $request): void
    {
        if (! $this->requiresCaptcha($email, $request)) {
            return;
        }

        $this->captcha->assertValid($token, $request);
    }

    /**
     * @throws ValidationException
     */
    public function assertNotLocked(string $email, Request $request): void
    {
        $user = User::query()->where('email', strtolower(trim($email)))->first();
        if ($user?->locked_until !== null && $user->locked_until->isFuture()) {
            $minutes = max(1, (int) now()->diffInMinutes($user->locked_until, false) * -1);
            $this->events->record('login_locked', $email, $user, $request);

            throw ValidationException::withMessages([
                'email' => ["Too many failed sign-in attempts. Try again in about {$minutes} minute(s)."],
            ])->status(429);
        }
    }

    public function recordFailure(string $email, Request $request, ?User $user = null): void
    {
        $normalized = strtolower(trim($email));
        $cacheKey = $this->failuresCacheKey($normalized, $request);
        $failures = $this->recentFailureCount($normalized, $request) + 1;
        Cache::put($cacheKey, $failures, now()->addHour());

        if ($user !== null) {
            $user->failed_login_attempts = ($user->failed_login_attempts ?? 0) + 1;
            $user->last_failed_login_at = now();

            $max = (int) config('security.login.max_failures_before_lock', 5);
            if ($user->failed_login_attempts >= $max) {
                $user->locked_until = now()->addMinutes($this->lockoutMinutesFor($user));
                $user->failed_login_attempts = 0;
            }

            $user->save();
        }

        $this->events->record('login_failed', $normalized, $user, $request, [
            'recent_failures' => $failures,
            'captcha_required' => $this->requiresCaptcha($normalized, $request),
        ]);
    }

    public function recordSuccess(User $user, Request $request): void
    {
        Cache::forget($this->failuresCacheKey($user->email, $request));
        $user->forceFill([
            'failed_login_attempts' => 0,
            'locked_until' => null,
            'last_failed_login_at' => null,
        ])->save();

        $this->events->record('login_success', $user->email, $user, $request);
    }

    public function captchaRequiredPayload(string $email, Request $request): array
    {
        return [
            'captcha_required' => true,
            'captcha_site_key' => $this->captcha->siteKey(),
            'message' => 'Complete the security check, then try signing in again.',
        ];
    }

    private function failuresCacheKey(string $email, Request $request): string
    {
        return 'login_failures:'.$this->cacheKey($email, $request);
    }

    private function lockoutMinutesFor(User $user): int
    {
        $steps = config('security.login.lockout_minutes', [1, 5, 15, 30]);
        if (! is_array($steps) || $steps === []) {
            return 5;
        }

        $round = (int) Cache::increment('login_lock_round:'.$user->id);
        Cache::put('login_lock_round:'.$user->id, $round, now()->addDay());
        $index = min(max($round - 1, 0), count($steps) - 1);

        return (int) $steps[$index];
    }
}
