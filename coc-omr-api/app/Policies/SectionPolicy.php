<?php

namespace App\Policies;

use App\Models\Section;
use App\Models\User;

class SectionPolicy
{
    use HandlesTeacherOwnership;

    public function archive(User $user, Section $section): bool
    {
        return $section->owner_teacher_id === $user->id;
    }
}
