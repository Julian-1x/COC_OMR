<?php

namespace App\Notifications;

use App\Services\PasswordResetEmailSender;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Notifications\Messages\MailMessage;

class ResetPasswordNotification extends ResetPassword
{
    /**
     * Password-reset link on the web portal (works in phone browser too).
     */
    protected function resetUrl(mixed $notifiable): string
    {
        return PasswordResetEmailSender::resetUrl($notifiable, $this->token);
    }

    public function toMail(mixed $notifiable): MailMessage
    {
        $url = $this->resetUrl($notifiable);

        return (new MailMessage)
            ->subject('Reset your COC OMR password')
            ->line('You are receiving this email because we received a password reset request for your account.')
            ->action('Reset password', $url)
            ->line('This link expires in '.config('auth.passwords.'.config('auth.defaults.passwords').'.expire', 60).' minutes.')
            ->line('If you did not request a reset, you can ignore this email.');
    }
}
