<?php

namespace App\Http\Middleware;

use Illuminate\Foundation\Http\Middleware\ValidateCsrfToken as Middleware;

/**
 * Web portal (omrweb.vercel.app) is listed in SANCTUM_STATEFUL_DOMAINS but authenticates
 * with Bearer personal access tokens, not Laravel session cookies. Cross-origin browsers
 * cannot attach Sanctum CSRF cookies, so token-authenticated API writes must skip CSRF.
 */
class VerifyCsrfToken extends Middleware
{
    /**
     * @param  \Illuminate\Http\Request  $request
     */
    protected function tokensMatch($request): bool
    {
        if ($request->bearerToken()) {
            return true;
        }

        return parent::tokensMatch($request);
    }
}
