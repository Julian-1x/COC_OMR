<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppRelease extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'build_number',
        'version_name',
        'download_url',
        'notes',
        'mandatory',
    ];

    protected function casts(): array
    {
        return [
            'build_number' => 'integer',
            'mandatory' => 'boolean',
            'created_at' => 'datetime',
        ];
    }
}
