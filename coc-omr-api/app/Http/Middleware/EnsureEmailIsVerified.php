<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureEmailIsVerified
{
    public function handle(Request $request, Closure $next): Response
    {
        if (config('app.auto_verify_email')) {
            return $next($request);
        }

        $user = $request->user();

        if (! $user
            || ($user instanceof MustVerifyEmail && ! $user->hasVerifiedEmail())) {
            return response()->json([
                'message' => 'Your email address is not verified.',
            ], 403);
        }

        return $next($request);
    }
}
