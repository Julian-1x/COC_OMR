<?php

namespace App\Notifications;

use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class AccountApprovedNotification extends Notification
{
    /**
     * @return list<string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $loginUrl = rtrim((string) config('app.frontend_url'), '/').'/login';

        return (new MailMessage)
            ->subject("You're approved — sign in to COC OMR")
            ->line('Good news — your COC OMR teacher account has been approved by your school admin.')
            ->line('You can sign in now on the phone app or the web portal with the same email and password.')
            ->action('Sign in on the web', $loginUrl)
            ->line('On your phone, open the COC OMR app and sign in there to scan answer sheets.');
    }
}
