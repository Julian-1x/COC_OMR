<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ScanResult extends Model
{
    use HasUuids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'owner_teacher_id',
        'student_omr_id',
        'subject_id',
        'subject_local_id',
        'subject_name',
        'sheet_id',
        'detected_answers',
        'correctness_map',
        'score',
        'total_questions',
        'confidence',
        'scan_time',
        'scanned_image_path',
        'review_reasons',
        'flagged_questions',
        'manually_confirmed',
        'needs_review',
        'local_id',
        'sync_status',
    ];

    protected function casts(): array
    {
        return [
            'detected_answers' => 'array',
            'correctness_map' => 'array',
            'review_reasons' => 'array',
            'flagged_questions' => 'array',
            'scan_time' => 'datetime',
            'score' => 'float',
            'confidence' => 'float',
            'total_questions' => 'integer',
            'manually_confirmed' => 'boolean',
            'needs_review' => 'boolean',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_teacher_id');
    }

    public function subject(): BelongsTo
    {
        return $this->belongsTo(Subject::class);
    }

    public function warnings(): HasMany
    {
        return $this->hasMany(ScanWarning::class);
    }
}
