<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Subject extends Model
{
    use HasUuids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'owner_teacher_id',
        'local_id',
        'name',
        'answer_key',
        'total_questions',
        'section_names',
        'section_qr_data',
        'exam_date',
        'passing_score',
        'use_partial_credit',
        'use_custom_layout',
        'options_count',
        'layout_shape',
        'custom_layout_id',
        'custom_grid_columns',
        'custom_grid_rows',
        'sync_status',
    ];

    protected function casts(): array
    {
        return [
            'answer_key' => 'array',
            'section_names' => 'array',
            'section_qr_data' => 'array',
            'exam_date' => 'date',
            'total_questions' => 'integer',
            'passing_score' => 'integer',
            'use_partial_credit' => 'boolean',
            'use_custom_layout' => 'boolean',
            'options_count' => 'integer',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_teacher_id');
    }

    public function scanResults(): HasMany
    {
        return $this->hasMany(ScanResult::class);
    }

    public function deadlines(): HasMany
    {
        return $this->hasMany(Deadline::class);
    }
}
