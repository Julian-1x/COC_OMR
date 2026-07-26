<?php

return [
    'name' => env('APP_NAME', 'COC OMR API'),
    'env' => env('APP_ENV', 'production'),
    'debug' => (bool) env('APP_DEBUG', false),
    'url' => env('APP_URL', 'http://localhost'),
    'timezone' => env('APP_TIMEZONE', 'UTC'),
    'locale' => env('APP_LOCALE', 'en'),
    'fallback_locale' => env('APP_FALLBACK_LOCALE', 'en'),
    'faker_locale' => env('APP_FAKER_LOCALE', 'en_US'),
    'cipher' => 'AES-256-CBC',
    'key' => env('APP_KEY'),
    'previous_keys' => [
        ...array_filter(
            explode(',', env('APP_PREVIOUS_KEYS', ''))
        ),
    ],
    'maintenance' => [
        'driver' => env('APP_MAINTENANCE_DRIVER', 'file'),
        'store' => env('APP_MAINTENANCE_STORE', 'database'),
    ],
    'auto_verify_email' => (bool) env('AUTO_VERIFY_EMAIL', false),
    'frontend_url' => env('FRONTEND_URL', 'http://localhost:3000'),
    'mobile_verify_redirect' => env('MOBILE_VERIFY_REDIRECT', 'edu.coc.omr://login-callback'),
    'mail_test_secret' => env('MAIL_TEST_SECRET', ''),
    // Comma-separated emails auto-promoted to school_admin on login/verify (free-plan bootstrap).
    'bootstrap_admin_emails' => env(
        'COC_BOOTSTRAP_ADMIN_EMAILS',
        'alex.balaba.coc@phinmaed.com',
    ),
];
