<?php

namespace App\Services;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Support\Facades\Log;

/**
 * Env-driven teacher approval when Render Shell / slow web admin is unavailable.
 */
class TeacherApprovalBootstrap
{
    /**
     * @return list<string>
     */
    public static function bootstrapEmails(): array
    {
        $raw = (string) config('app.bootstrap_approve_emails', '');
        if ($raw === '') {
            return [];
        }

        return array_values(array_filter(array_map(
            static fn (string $email): string => strtolower(trim($email)),
            explode(',', $raw),
        )));
    }

    public static function shouldBootstrap(string $email): bool
    {
        $normalized = strtolower(trim($email));

        return $normalized !== '' && in_array($normalized, self::bootstrapEmails(), true);
    }

    /**
     * Approve a matching user if they are still pending. Returns true when a change was applied.
     */
    public static function approveIfListed(User $user): bool
    {
        if (! self::shouldBootstrap((string) $user->email)) {
            return false;
        }

        $user->loadMissing('teacherProfile');
        $profile = $user->teacherProfile;
        if ($profile === null) {
            return false;
        }

        if ($profile->access_status === CocSchool::ACCESS_APPROVED && $profile->is_active) {
            return false;
        }

        if (CocSchool::isAccessAdminRole((string) $profile->role)) {
            return false;
        }

        $profile->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        if ($profile->school_name === null || $profile->school_name === '') {
            $profile->school_name = CocSchool::NAME;
        }
        $profile->save();

        Log::info('COC teacher approval bootstrap approved user', [
            'email' => $user->email,
            'user_id' => $user->id,
        ]);

        return true;
    }

    /**
     * Approve all emails listed in COC_BOOTSTRAP_APPROVE_EMAILS (idempotent).
     *
     * @return int Number of accounts approved on this run
     */
    public static function approvePendingFromEnv(): int
    {
        $approved = 0;
        foreach (self::bootstrapEmails() as $email) {
            if (self::approveEmailInDatabase($email)) {
                $approved += 1;
            }
        }

        return $approved;
    }

    public static function approveEmailInDatabase(string $email): bool
    {
        $normalized = strtolower(trim($email));
        $user = User::query()->where('email', $normalized)->with('teacherProfile')->first();
        if ($user === null) {
            return false;
        }

        return self::approveIfListed($user);
    }
}
