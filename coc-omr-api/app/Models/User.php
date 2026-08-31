<?php

namespace App\Models;

use App\Support\CocSchool;
use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use App\Notifications\ResetPasswordNotification;
use App\Services\PasswordResetEmailSender;
use App\Services\VerificationEmailSender;
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
        'two_factor_secret',
        'two_factor_recovery_codes',
        'two_factor_confirmed_at',
        'locked_until',
        'failed_login_attempts',
        'last_failed_login_at',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'two_factor_secret',
        'two_factor_recovery_codes',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'two_factor_confirmed_at' => 'datetime',
            'locked_until' => 'datetime',
            'last_failed_login_at' => 'datetime',
            'failed_login_attempts' => 'integer',
        ];
    }

    public function teacherProfile(): HasOne
    {
        return $this->hasOne(TeacherProfile::class, 'id');
    }

    public function isSuperAdmin(): bool
    {
        $profile = $this->teacherProfile;

        if (! $profile || ! $profile->isApproved()) {
            return false;
        }

        return CocSchool::isSuperAdminRole((string) $profile->role);
    }

    public function isDeptAdmin(): bool
    {
        $profile = $this->teacherProfile;

        if (! $profile || ! $profile->isApproved()) {
            return false;
        }

        return $profile->role === CocSchool::ROLE_DEPT_ADMIN
            && is_string($profile->department)
            && CocSchool::isValidDepartment($profile->department);
    }

    /**
     * Can open Access control (super or department admin).
     */
    public function canManageAccess(): bool
    {
        return $this->isSuperAdmin() || $this->isDeptAdmin();
    }

    /**
     * @deprecated Prefer canManageAccess() / isSuperAdmin() / isDeptAdmin().
     */
    public function isSchoolAdmin(): bool
    {
        return $this->canManageAccess();
    }

    public function isAccessApproved(): bool
    {
        return $this->teacherProfile?->isApproved() ?? false;
    }

    public function schoolName(): ?string
    {
        return $this->teacherProfile?->school_name;
    }

    public function department(): ?string
    {
        $department = $this->teacherProfile?->department;

        return is_string($department) && $department !== ''
            ? CocSchool::normalizeDepartment($department)
            : null;
    }

    public function canManageTeacherProfile(TeacherProfile $teacher): bool
    {
        if ($this->isSuperAdmin()) {
            return true;
        }

        if (! $this->isDeptAdmin()) {
            return false;
        }

        $adminDept = $this->department();
        $teacherDept = is_string($teacher->department) && $teacher->department !== ''
            ? CocSchool::normalizeDepartment($teacher->department)
            : null;

        return $adminDept !== null
            && $teacherDept !== null
            && $adminDept === $teacherDept;
    }

    public function teacherInSameSchool(string $teacherId): bool
    {
        if (! $this->canManageAccess()) {
            return false;
        }

        $school = $this->schoolName();
        if ($school === null || $school === '') {
            return false;
        }

        $other = TeacherProfile::query()->find($teacherId);
        if ($other === null) {
            return false;
        }

        if ($this->isSuperAdmin() && $school === CocSchool::NAME) {
            return true;
        }

        if ($this->isDeptAdmin()) {
            return $this->canManageTeacherProfile($other);
        }

        return $other->school_name !== null
            && $other->school_name === $school;
    }

    public function sendEmailVerificationNotification(): void
    {
        $result = VerificationEmailSender::send($this);
        if (! $result['ok']) {
            throw new \RuntimeException($result['error'] ?? 'Verification email could not be sent.');
        }
    }

    public function sendPasswordResetNotification($token): void
    {
        $result = PasswordResetEmailSender::send($this, $token);
        if (! $result['ok']) {
            throw new \RuntimeException($result['error'] ?? 'Password reset email could not be sent.');
        }
    }
}
