<?php

namespace App\Policies;

use App\Models\User;
use Illuminate\Database\Eloquent\Model;

trait HandlesTeacherOwnership
{
    protected function ownerTeacherId(Model $model): ?string
    {
        return $model->owner_teacher_id ?? null;
    }

    public function viewAny(User $user): bool
    {
        return true;
    }

    public function view(User $user, Model $model): bool
    {
        $ownerId = $this->ownerTeacherId($model);

        if ($ownerId === $user->id) {
            return true;
        }

        return $user->isSchoolAdmin() && $user->teacherInSameSchool($ownerId);
    }

    public function create(User $user): bool
    {
        return true;
    }

    public function update(User $user, Model $model): bool
    {
        return $this->ownerTeacherId($model) === $user->id;
    }

    public function delete(User $user, Model $model): bool
    {
        return $this->ownerTeacherId($model) === $user->id;
    }

    public function restore(User $user, Model $model): bool
    {
        return $this->ownerTeacherId($model) === $user->id;
    }

    public function forceDelete(User $user, Model $model): bool
    {
        return $this->ownerTeacherId($model) === $user->id;
    }
}
