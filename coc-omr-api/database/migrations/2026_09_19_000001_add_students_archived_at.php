<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->timestamp('archived_at')->nullable()->after('sync_status');
            $table->index(['owner_teacher_id', 'archived_at']);
        });
    }

    public function down(): void
    {
        Schema::table('students', function (Blueprint $table) {
            $table->dropIndex(['owner_teacher_id', 'archived_at']);
            $table->dropColumn('archived_at');
        });
    }
};
