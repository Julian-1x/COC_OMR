<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Student extends Model
{
    use HasUuids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'owner_teacher_id',
        'school_id',
        'omr_id',
        'name',
        'section_name',
        'score',
        'answers',
        'scan_date',
        'confidence',
        'local_id',
        'sync_status',
    ];

    protected function casts(): array
    {
        return [
            'answers' => 'array',
            'scan_date' => 'datetime',
            'score' => 'float',
            'confidence' => 'float',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_teacher_id');
    }
}
