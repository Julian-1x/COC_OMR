<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\TeacherApprovalBootstrap;
use App\Support\CocSchool;
use Illuminate\Console\Command;

class ApproveTeacherCommand extends Command
{
    protected $signature = 'omr:approve-teacher {email : Teacher email to approve for app access}';

    protected $description = 'Approve a registered teacher (sets access_status=approved). Use when Access control is unreachable.';

    public function handle(): int
    {
        $email = strtolower(trim((string) $this->argument('email')));
        $user = User::query()->where('email', $email)->with('teacherProfile')->first();

        if ($user === null) {
            $this->error("No user found for {$email}. They must register first.");

            return self::FAILURE;
        }

        $profile = $user->teacherProfile;
        if ($profile === null) {
            $this->error('User has no teacher profile.');

            return self::FAILURE;
        }

        if (! $user->hasVerifiedEmail() && ! config('app.auto_verify_email')) {
            $this->warn('Email is not verified yet. They must confirm email before they can sign in.');
        }

        if ($profile->access_status === CocSchool::ACCESS_APPROVED && $profile->is_active) {
            $this->info("{$email} is already approved.");

            return self::SUCCESS;
        }

        $profile->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        if ($profile->school_name === null || $profile->school_name === '') {
            $profile->school_name = CocSchool::NAME;
        }
        $profile->save();

        $this->info("Approved {$email}. They can sign in on the app or web after email confirmation.");

        return self::SUCCESS;
    }
}
