<?php

namespace App\Services;

use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\Subject;
use App\Models\TeacherProfile;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

class TeacherScopeService
{
    public function sectionsQuery(User $user): Builder
    {
        return $this->scopedQuery($user, Section::query());
    }

    public function studentsQuery(User $user): Builder
    {
        return $this->scopedQuery($user, Student::query());
    }

    public function subjectsQuery(User $user): Builder
    {
        return $this->scopedQuery($user, Subject::query());
    }

    public function scanResultsQuery(User $user): Builder
    {
        return $this->scopedQuery($user, ScanResult::query());
    }

    public function deadlinesQuery(User $user): Builder
    {
        return $this->scopedQuery($user, Deadline::query());
    }

    public function schoolTeachersQuery(User $user): Builder
    {
        $school = $user->schoolName();
        if ($school === null || $school === '') {
            return TeacherProfile::query()->whereRaw('1 = 0');
        }

        return TeacherProfile::query()
            ->where('school_name', $school)
            ->orderBy('full_name');
    }

    /**
     * @template T of Model
     *
     * @param  Builder<T>  $query
     * @return Builder<T>
     */
    private function scopedQuery(User $user, Builder $query): Builder
    {
        if ($user->isSchoolAdmin()) {
            $school = $user->schoolName();
            if ($school === null || $school === '') {
                return $query->where('owner_teacher_id', $user->id);
            }

            $teacherIds = TeacherProfile::query()
                ->where('school_name', $school)
                ->pluck('id');

            return $query->whereIn('owner_teacher_id', $teacherIds);
        }

        return $query->where('owner_teacher_id', $user->id);
    }
}
