<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Console\Command;

class PromoteAdminCommand extends Command
{
    protected $signature = 'omr:promote-admin
                            {email : Teacher email to promote}
                            {--demote : Remove school_admin role (keeps approved teacher access)}';

    protected $description = 'Promote a verified teacher to school_admin for COC (or demote).';

    public function handle(): int
    {
        $email = strtolower(trim((string) $this->argument('email')));
        $user = User::query()->where('email', $email)->with('teacherProfile')->first();

        if ($user === null) {
            $this->error("No user found for {$email}. Have them register and verify email first.");

            return self::FAILURE;
        }

        $profile = $user->teacherProfile;
        if ($profile === null) {
            $this->error('User has no teacher profile.');

            return self::FAILURE;
        }

        if ($this->option('demote')) {
            $profile->role = 'teacher';
            $profile->applyAccessStatus(CocSchool::ACCESS_APPROVED);
            $profile->school_name = $profile->school_name ?: CocSchool::NAME;
            $profile->save();

            $this->info("Demoted {$email} to teacher (still approved).");

            return self::SUCCESS;
        }

        if (! $user->hasVerifiedEmail() && ! config('app.auto_verify_email')) {
            $this->warn('Email is not verified yet. Promoting anyway — they still need to verify before login.');
        }

        $profile->role = 'school_admin';
        $profile->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $profile->school_name = CocSchool::NAME;
        $profile->save();

        $this->info("Promoted {$email} to school_admin at ".CocSchool::NAME.'.');
        $this->line('They can sign in on the web and open Dashboard → Admin → Access control.');

        return self::SUCCESS;
    }
}
