<?php

namespace App\Notifications;

use App\Services\VerificationEmailSender;
use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Notifications\Messages\MailMessage;

class VerifyEmailNotification extends VerifyEmail
{
    public function __construct(
        private readonly string $preferredPlatform = 'web',
    ) {}

    public function toMail($notifiable): MailMessage
    {
        $platform = VerificationEmailSender::normalizePlatform($this->preferredPlatform);
        $email = (string) $notifiable->getEmailForVerification();
        $url = VerificationEmailSender::verificationUrl($notifiable, $platform);

        if ($platform === 'mobile') {
            return (new MailMessage)
                ->subject('Verify your COC OMR email')
                ->line('You are receiving this email because we received a registration request for your COC OMR account.')
                ->line('This link confirms: '.$email)
                ->line('You signed up in the phone app. Tap the button below to finish inside COC OMR.')
                ->action('Verify in COC OMR app', $url)
                ->line('This link expires in 60 minutes. If you did not request this, you can ignore this email.');
        }

        return (new MailMessage)
            ->subject('Verify your COC OMR email')
            ->line('You are receiving this email because we received a registration request for your COC OMR account.')
            ->line('This link confirms: '.$email)
            ->line('You signed up on the web. Tap below to confirm in your browser.')
            ->line('Leave the sign-in page open — it can continue after you verify.')
            ->action('Verify email', $url)
            ->line('This link expires in 60 minutes. If you did not request this, you can ignore this email.');
    }
}
