<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Introduce super_admin / dept_admin hierarchy.
 * Existing school_admin / admin accounts become super_admin.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('teacher_profiles')
            ->whereIn('role', ['school_admin', 'admin'])
            ->update(['role' => 'super_admin']);
    }

    public function down(): void
    {
        DB::table('teacher_profiles')
            ->where('role', 'super_admin')
            ->update(['role' => 'school_admin']);

        DB::table('teacher_profiles')
            ->where('role', 'dept_admin')
            ->update(['role' => 'teacher']);
    }
};
