<?php

namespace App\Services;

use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\Subject;
use App\Models\TeacherProfile;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

class TeacherScopeService
{
    /**
     * Teacher-desk queries: always the signed-in teacher's own rows.
     * School-wide admin reads use schoolWide* methods instead.
     */
    public function sectionsQuery(User $user): Builder
    {
        return Section::query()->where('owner_teacher_id', $user->id);
    }

    public function studentsQuery(User $user): Builder
    {
        return Student::query()->where('owner_teacher_id', $user->id);
    }

    public function subjectsQuery(User $user): Builder
    {
        return Subject::query()->where('owner_teacher_id', $user->id);
    }

    public function scanResultsQuery(User $user): Builder
    {
        return ScanResult::query()->where('owner_teacher_id', $user->id);
    }

    public function deadlinesQuery(User $user): Builder
    {
        return Deadline::query()->where('owner_teacher_id', $user->id);
    }

    public function schoolTeachersQuery(User $user): Builder
    {
        $school = $user->schoolName();
        if ($school === null || $school === '') {
            return TeacherProfile::query()->whereRaw('1 = 0');
        }

        // Single-tenant COC: school admins see every teacher, including older
        // accounts that typed a different free-text school name.
        if ($school === CocSchool::NAME) {
            return TeacherProfile::query()->orderBy('full_name');
        }

        return TeacherProfile::query()
            ->where('school_name', $school)
            ->orderBy('full_name');
    }

    public function schoolWideSectionsQuery(User $user): Builder
    {
        return $this->schoolWideQuery($user, Section::query());
    }

    public function schoolWideStudentsQuery(User $user): Builder
    {
        return $this->schoolWideQuery($user, Student::query());
    }

    public function schoolWideSubjectsQuery(User $user): Builder
    {
        return $this->schoolWideQuery($user, Subject::query());
    }

    public function schoolWideScanResultsQuery(User $user): Builder
    {
        return $this->schoolWideQuery($user, ScanResult::query());
    }

    /**
     * @template T of Model
     *
     * @param  Builder<T>  $query
     * @return Builder<T>
     */
    private function schoolWideQuery(User $user, Builder $query): Builder
    {
        if (! $user->isSchoolAdmin()) {
            return $query->where('owner_teacher_id', $user->id);
        }

        $school = $user->schoolName();
        if ($school === null || $school === '') {
            return $query->where('owner_teacher_id', $user->id);
        }

        if ($school === CocSchool::NAME) {
            return $query;
        }

        $teacherIds = TeacherProfile::query()
            ->where('school_name', $school)
            ->pluck('id');

        return $query->whereIn('owner_teacher_id', $teacherIds);
    }
}
