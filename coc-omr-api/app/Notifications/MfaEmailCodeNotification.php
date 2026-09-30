<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class MfaEmailCodeNotification extends Notification
{
    public function __construct(private readonly string $code) {}

    public function plainCode(): string
    {
        return $this->code;
    }

    /**
     * @return list<string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $minutes = (int) config('security.mfa.email_otp_ttl_minutes', 10);

        return (new MailMessage)
            ->subject('Your COC OMR sign-in code')
            ->line('Use this one-time code to finish signing in:')
            ->line('**'.$this->code.'**')
            ->line("This code expires in {$minutes} minutes.")
            ->line('If you did not try to sign in, you can ignore this email.');
    }
}
