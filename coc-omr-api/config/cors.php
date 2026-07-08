<?php

$frontend = rtrim((string) env('FRONTEND_URL', 'http://localhost:3000'), '/');
$extra = array_filter(array_map('trim', explode(',', (string) env('CORS_EXTRA_ORIGINS', ''))));

return [
    'paths' => ['api/*', 'sanctum/csrf-cookie'],
    'allowed_methods' => ['*'],
    'allowed_origins' => array_values(array_unique(array_filter([
        'http://localhost:3000',
        $frontend,
        ...$extra,
    ]))),
    'allowed_origins_patterns' => [],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => true,
];
