<?php

namespace App\Services\Auth;

use App\Models\AuthEvent;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CaptchaVerifier
{
    public function isEnabled(): bool
    {
        if (! config('security.captcha.enabled')) {
            return false;
        }

        $secret = (string) config('security.captcha.secret_key');

        return $secret !== '';
    }

    public function siteKey(): ?string
    {
        $key = (string) config('security.captcha.site_key');

        return $key !== '' ? $key : null;
    }

    /**
     * @throws ValidationException
     */
    public function assertValid(?string $token, Request $request, string $field = 'captcha_token'): void
    {
        if (! $this->isEnabled()) {
            return;
        }

        if ($token === null || trim($token) === '') {
            throw ValidationException::withMessages([
                $field => ['Complete the security check, then try again.'],
            ])->status(422);
        }

        $response = Http::asForm()
            ->timeout(8)
            ->post('https://challenges.cloudflare.com/turnstile/v0/siteverify', [
                'secret' => config('security.captcha.secret_key'),
                'response' => $token,
                'remoteip' => $request->ip(),
            ]);

        if (! $response->ok()) {
            throw ValidationException::withMessages([
                $field => ['Security check could not be verified. Try again in a moment.'],
            ]);
        }

        $body = $response->json();
        if (! ($body['success'] ?? false)) {
            throw ValidationException::withMessages([
                $field => ['Security check failed. Refresh the page and try again.'],
            ]);
        }
    }
}
