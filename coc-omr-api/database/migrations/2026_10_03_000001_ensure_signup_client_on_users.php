<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Production safety: older deploys may have recorded the signup_client migration
 * without the column existing (or DB was restored without it). Always ensure it.
 *
 * Same Neon/pooler rules as 2026_09_19 students.archived_at.
 */
return new class extends Migration
{
    public $withinTransaction = false;

    public function up(): void
    {
        DB::statement(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS signup_client varchar(16) NOT NULL DEFAULT 'web'",
        );
    }

    public function down(): void
    {
        // Keep column — dropping would break verify-link platform routing.
    }
};
