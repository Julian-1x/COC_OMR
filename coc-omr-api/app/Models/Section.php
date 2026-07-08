<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Section extends Model
{
    use HasUuids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'owner_teacher_id',
        'name',
        'teacher',
        'student_count',
        'school_year',
        'term_label',
        'archived_at',
        'local_id',
        'sync_status',
    ];

    protected function casts(): array
    {
        return [
            'archived_at' => 'datetime',
            'student_count' => 'integer',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_teacher_id');
    }
}
