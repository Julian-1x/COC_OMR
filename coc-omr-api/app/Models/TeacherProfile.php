<?php

namespace App\Models;

use App\Support\CocSchool;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TeacherProfile extends Model
{
    use HasUuids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'full_name',
        'role',
        'is_active',
        'access_status',
        'school_name',
        'department',
        'pin_hash',
        'pin_salt',
    ];

    protected $hidden = [
        'pin_hash',
        'pin_salt',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'id');
    }

    public function isApproved(): bool
    {
        return $this->access_status === CocSchool::ACCESS_APPROVED
            && $this->is_active;
    }

    public function applyAccessStatus(string $status): void
    {
        if (! CocSchool::isValidAccessStatus($status)) {
            throw new \InvalidArgumentException("Invalid access_status: {$status}");
        }

        $this->access_status = $status;
        $this->is_active = $status === CocSchool::ACCESS_APPROVED;
    }
}
