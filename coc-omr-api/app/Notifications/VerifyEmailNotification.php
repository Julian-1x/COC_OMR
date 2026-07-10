<?php

namespace App\Notifications;

use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\URL;

class VerifyEmailNotification extends VerifyEmail
{
    protected function verificationUrl($notifiable, string $platform): string
    {
        return URL::temporarySignedRoute(
            'verification.verify',
            Carbon::now()->addMinutes(Config::get('auth.verification.expire', 60)),
            [
                'id' => $notifiable->getKey(),
                'hash' => sha1($notifiable->getEmailForVerification()),
                'platform' => $platform,
            ],
        );
    }

    public function toMail($notifiable): MailMessage
    {
        $webUrl = $this->verificationUrl($notifiable, 'web');
        $mobileUrl = $this->verificationUrl($notifiable, 'mobile');

        return (new MailMessage)
            ->subject('Verify your COC OMR email')
            ->line('Tap the button below to verify your email and finish signing in.')
            ->action('Verify email (web)', $webUrl)
            ->line('On your phone? Open this link in the browser, then return to the app:')
            ->line($mobileUrl);
    }
}
