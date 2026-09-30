<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Login rate limiting & lockout
    |--------------------------------------------------------------------------
    */
    'login' => [
        // Per IP (all emails combined).
        'ip_per_minute' => (int) env('LOGIN_IP_PER_MINUTE', 20),
        // Per email + IP pair.
        'email_per_minute' => (int) env('LOGIN_EMAIL_PER_MINUTE', 8),
        // Failed password attempts before temporary lockout.
        'max_failures_before_lock' => (int) env('LOGIN_MAX_FAILURES', 5),
        // Escalating lockout minutes (repeats last value).
        'lockout_minutes' => [1, 5, 15, 30],
        // Show CAPTCHA after this many recent failures (email + IP).
        'captcha_after_failures' => (int) env('LOGIN_CAPTCHA_AFTER_FAILURES', 3),
    ],

    'register' => [
        'ip_per_minute' => (int) env('REGISTER_IP_PER_MINUTE', 5),
    ],

    /*
    |--------------------------------------------------------------------------
    | Cloudflare Turnstile (or disabled when keys empty)
    |--------------------------------------------------------------------------
    */
    'captcha' => [
        'enabled' => filter_var(env('CAPTCHA_ENABLED', false), FILTER_VALIDATE_BOOL),
        'site_key' => env('CAPTCHA_SITE_KEY'),
        'secret_key' => env('CAPTCHA_SECRET_KEY'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Multi-factor authentication (TOTP)
    |--------------------------------------------------------------------------
    */
    'mfa' => [
        'issuer' => env('MFA_ISSUER', 'COC OMR'),
        // Every approved account must enroll authenticator (teachers + admins).
        'required_roles' => ['super_admin', 'dept_admin', 'teacher'],
        'challenge_ttl_minutes' => (int) env('MFA_CHALLENGE_TTL_MINUTES', 15),
        // Optional email OTP backup when authenticator is unavailable.
        'email_otp_ttl_minutes' => (int) env('MFA_EMAIL_OTP_TTL_MINUTES', 10),
        'email_otp_resend_seconds' => (int) env('MFA_EMAIL_OTP_RESEND_SECONDS', 60),
        'email_otp_max_sends_per_hour' => (int) env('MFA_EMAIL_OTP_MAX_SENDS_PER_HOUR', 5),
    ],

];
