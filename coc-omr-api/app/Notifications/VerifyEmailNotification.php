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

        $email = (string) $notifiable->getEmailForVerification();

        return (new MailMessage)
            ->subject('Verify your COC OMR email')
            ->line('You are receiving this email because we received a registration request for your COC OMR account.')
            ->line('This link confirms: '.$email)
            ->line('If you registered on the web, leave that sign-in page open — it can continue after you verify.')
            ->line('On a shared phone: open this link even if another Google inbox or another COC OMR teacher was signed in. After verify you will see a confirmation for this email (any other web session is cleared).')
            ->action('Verify email', $webUrl)
            ->line('Prefer the mobile app?')
            ->line($mobileUrl)
            ->line('This link expires in 60 minutes. If you did not request this, you can ignore this email.');
    }
}
