<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Services\Auth\CaptchaVerifier;
use Illuminate\Http\JsonResponse;

class SecurityConfigController extends Controller
{
    public function __invoke(CaptchaVerifier $captcha): JsonResponse
    {
        return response()->json([
            'captcha_enabled' => $captcha->isEnabled(),
            'captcha_site_key' => $captcha->siteKey(),
            'mfa_available' => true,
        ]);
    }
}
