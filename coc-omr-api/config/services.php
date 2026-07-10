<?php

return [
    'brevo' => [
        'api_key' => trim((string) env('BREVO_API_KEY', '')),
    ],
];
