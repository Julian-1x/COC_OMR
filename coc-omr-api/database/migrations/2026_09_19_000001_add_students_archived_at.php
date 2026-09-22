<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Catch-up for DBs created before students.archived_at lived in the base
 * schema. Fresh installs already have column+index — use Postgres IF NOT
 * EXISTS and skip Laravel's migration transaction (Schema::hasColumn inside
 * a failed txn only surfaces 25P02 and masks the real error).
 */
return new class extends Migration
{
    /** @var bool */
    public $withinTransaction = false;

    public function up(): void
    {
        DB::statement('ALTER TABLE students ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP(0) WITHOUT TIME ZONE NULL');
        DB::statement('CREATE INDEX IF NOT EXISTS students_owner_teacher_id_archived_at_index ON students (owner_teacher_id, archived_at)');
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS students_owner_teacher_id_archived_at_index');
        DB::statement('ALTER TABLE students DROP COLUMN IF EXISTS archived_at');
    }
};
