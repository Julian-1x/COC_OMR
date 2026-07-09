<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Mail;

class MailTestCommand extends Command
{
    protected $signature = 'mail:test {email : Recipient address for the test message}';

    protected $description = 'Show mail config and send one test message (use on Render Shell).';

    public function handle(): int
    {
        $mailer = (string) config('mail.default');
        $host = (string) config('mail.mailers.smtp.host');
        $port = (string) config('mail.mailers.smtp.port');
        $encryption = (string) config('mail.mailers.smtp.encryption');
        $username = (string) config('mail.mailers.smtp.username');
        $from = (string) config('mail.from.address');

        $this->line('Mail configuration:');
        $this->table(
            ['Setting', 'Value'],
            [
                ['MAIL_MAILER (default)', $mailer],
                ['MAIL_HOST', $host],
                ['MAIL_PORT', $port],
                ['MAIL_ENCRYPTION', $encryption !== '' ? $encryption : '(none)'],
                ['MAIL_USERNAME', $username !== '' ? $username : '(missing)'],
                ['MAIL_PASSWORD', config('mail.mailers.smtp.password') ? '(set)' : '(missing)'],
                ['MAIL_FROM_ADDRESS', $from !== '' ? $from : '(missing)'],
            ],
        );

        if ($mailer !== 'smtp') {
            $this->error('MAIL_MAILER is not smtp — emails only go to server logs, not Brevo.');
            $this->line('On Render → Environment, set MAIL_MAILER=smtp and redeploy.');

            return self::FAILURE;
        }

        if ($username === '' || $from === '' || ! config('mail.mailers.smtp.password')) {
            $this->error('SMTP username, password, or FROM address is missing on the server.');

            return self::FAILURE;
        }

        $email = strtolower($this->argument('email'));

        try {
            Mail::raw(
                'COC OMR mail test — if you received this, Brevo SMTP is working.',
                static function ($message) use ($email): void {
                    $message->to($email)->subject('COC OMR mail test');
                },
            );
        } catch (\Throwable $exception) {
            $this->error('Send failed: '.$exception->getMessage());

            return self::FAILURE;
        }

        $this->info("Test message handed off to SMTP for {$email}.");
        $this->line('Check Brevo → Transactional → Logs, then the recipient inbox/spam.');

        return self::SUCCESS;
    }
}
