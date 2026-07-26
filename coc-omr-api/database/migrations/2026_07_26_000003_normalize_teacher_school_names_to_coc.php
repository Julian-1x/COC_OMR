<?php

use App\Support\CocSchool;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Heal older free-text school labels so COC admin lists see every teacher.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('teacher_profiles')
            ->where(function ($query) {
                $query->whereNull('school_name')
                    ->orWhere('school_name', '!=', CocSchool::NAME);
            })
            ->update([
                'school_name' => CocSchool::NAME,
            ]);
    }

    public function down(): void
    {
        // Irreversible data heal for single-tenant COC.
    }
};
