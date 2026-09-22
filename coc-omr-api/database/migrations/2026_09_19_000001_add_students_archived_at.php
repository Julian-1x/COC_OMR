<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Older DBs may lack students.archived_at. Fresh installs already have it
 * from create_coc_omr_tables — keep this idempotent for Postgres/Render.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('students')) {
            return;
        }

        if (! Schema::hasColumn('students', 'archived_at')) {
            Schema::table('students', function (Blueprint $table) {
                $table->timestamp('archived_at')->nullable();
            });
        }

        if (! Schema::hasColumn('students', 'archived_at')) {
            return;
        }

        $indexExists = collect(Schema::getIndexes('students'))->contains(function (array $index) {
            return ($index['name'] ?? '') === 'students_owner_teacher_id_archived_at_index'
                || ($index['columns'] ?? []) === ['owner_teacher_id', 'archived_at'];
        });

        if (! $indexExists) {
            Schema::table('students', function (Blueprint $table) {
                $table->index(['owner_teacher_id', 'archived_at']);
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasTable('students') || ! Schema::hasColumn('students', 'archived_at')) {
            return;
        }

        $indexName = collect(Schema::getIndexes('students'))->first(function (array $index) {
            return ($index['name'] ?? '') === 'students_owner_teacher_id_archived_at_index'
                || ($index['columns'] ?? []) === ['owner_teacher_id', 'archived_at'];
        });

        Schema::table('students', function (Blueprint $table) use ($indexName) {
            if ($indexName !== null) {
                $table->dropIndex($indexName['name'] ?? ['owner_teacher_id', 'archived_at']);
            }
            $table->dropColumn('archived_at');
        });
    }
};
