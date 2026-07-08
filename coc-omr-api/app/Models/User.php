<?php

namespace App\Models;

use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use App\Notifications\VerifyEmailNotification;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements MustVerifyEmail
{
    use HasApiTokens;
    use HasFactory;
    use HasUuids;
    use Notifiable;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'name',
        'email',
        'password',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function teacherProfile(): HasOne
    {
        return $this->hasOne(TeacherProfile::class, 'id');
    }

    public function isSchoolAdmin(): bool
    {
        $profile = $this->teacherProfile;

        if (! $profile || ! $profile->is_active) {
            return false;
        }

        return in_array($profile->role, ['admin', 'school_admin'], true);
    }

    public function schoolName(): ?string
    {
        return $this->teacherProfile?->school_name;
    }

    public function teacherInSameSchool(string $teacherId): bool
    {
        $school = $this->schoolName();
        if ($school === null || $school === '') {
            return false;
        }

        $other = TeacherProfile::query()->find($teacherId);

        return $other !== null
            && $other->school_name !== null
            && $other->school_name === $school;
    }

    public function sendEmailVerificationNotification(): void
    {
        $this->notify(new VerifyEmailNotification);
    }
}
