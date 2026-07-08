<?php

namespace App\Services;

use App\Models\Subject;
use App\Models\User;

class SubjectResolver
{
    public function resolveCloudSubjectId(User $user, ?string $subjectLocalId): ?string
    {
        if ($subjectLocalId === null || $subjectLocalId === '') {
            return null;
        }

        $subject = Subject::query()
            ->where('owner_teacher_id', $user->id)
            ->where('local_id', $subjectLocalId)
            ->first();

        return $subject?->id;
    }
}
