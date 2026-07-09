<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;

class BrevoMailService
{
    public static function sendTransactional(
        string $to,
        string $subject,
        string $html,
        ?string $text = null,
    ): void {
        $apiKey = (string) config('services.brevo.api_key');
        if ($apiKey === '') {
            throw new RuntimeException('BREVO_API_KEY is not configured on the server.');
        }

        $fromAddress = (string) config('mail.from.address');
        $fromName = (string) config('mail.from.name');
        if ($fromAddress === '') {
            throw new RuntimeException('MAIL_FROM_ADDRESS is not configured on the server.');
        }

        $response = Http::timeout(20)
            ->withHeaders([
                'api-key' => $apiKey,
                'accept' => 'application/json',
            ])
            ->post('https://api.brevo.com/v3/smtp/email', [
                'sender' => [
                    'name' => $fromName,
                    'email' => $fromAddress,
                ],
                'to' => [
                    ['email' => $to],
                ],
                'subject' => $subject,
                'htmlContent' => $html,
                'textContent' => $text ?? trim(strip_tags($html)),
            ]);

        if (! $response->successful()) {
            throw new RuntimeException(
                'Brevo API '.$response->status().': '.$response->body(),
            );
        }
    }
}
