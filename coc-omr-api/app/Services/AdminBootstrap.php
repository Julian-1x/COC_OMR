<?php

namespace App\Services;

use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Support\Facades\Log;

/**
 * One-time / env-driven promotion for the first COC school admin(s)
 * when Render Shell is unavailable on the free plan.
 */
class AdminBootstrap
{
    /**
     * @return list<string>
     */
    public static function bootstrapEmails(): array
    {
        $raw = (string) config('app.bootstrap_admin_emails', '');
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
     * Promote a matching user to school_admin + approved + COC school.
     * Returns true when a change was applied.
     */
    public static function promoteIfListed(User $user): bool
    {
        if (! self::shouldBootstrap((string) $user->email)) {
            return false;
        }

        $user->loadMissing('teacherProfile');
        $profile = $user->teacherProfile;
        if ($profile === null) {
            return false;
        }

        $alreadyAdmin = in_array($profile->role, ['admin', 'school_admin'], true)
            && $profile->isApproved()
            && $profile->school_name === CocSchool::NAME;

        if ($alreadyAdmin) {
            return false;
        }

        $profile->role = 'school_admin';
        $profile->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $profile->school_name = CocSchool::NAME;
        $profile->save();

        Log::info('COC admin bootstrap promoted user', [
            'email' => $user->email,
            'user_id' => $user->id,
        ]);

        return true;
    }

    /**
     * Used by migrations when Shell is unavailable.
     */
    public static function promoteEmailInDatabase(string $email): bool
    {
        $normalized = strtolower(trim($email));
        $user = User::query()->where('email', $normalized)->with('teacherProfile')->first();
        if ($user === null) {
            return false;
        }

        $profile = $user->teacherProfile;
        if ($profile === null) {
            TeacherProfile::query()->create([
                'id' => $user->id,
                'full_name' => $user->name ?: $normalized,
                'role' => 'school_admin',
                'is_active' => true,
                'access_status' => CocSchool::ACCESS_APPROVED,
                'school_name' => CocSchool::NAME,
            ]);

            return true;
        }

        $profile->role = 'school_admin';
        $profile->applyAccessStatus(CocSchool::ACCESS_APPROVED);
        $profile->school_name = CocSchool::NAME;
        $profile->save();

        return true;
    }
}
