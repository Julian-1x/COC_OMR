<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Neon / PgBouncer: Schema::hasColumn inside a migration transaction can
     * abort the TX; later ALTER then fails with SQLSTATE 25P02.
     */
    public $withinTransaction = false;

    public function up(): void
    {
        // Where the teacher signed up: mobile app vs web portal.
        DB::statement(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS signup_client varchar(16) NOT NULL DEFAULT 'web'",
        );
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE users DROP COLUMN IF EXISTS signup_client');
    }
};
