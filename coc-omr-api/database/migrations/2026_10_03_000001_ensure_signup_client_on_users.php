<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Production safety: older deploys may have recorded the signup_client migration
 * without the column existing (or DB was restored without it). Always ensure it.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasColumn('users', 'signup_client')) {
            return;
        }

        Schema::table('users', function (Blueprint $table) {
            $table->string('signup_client', 16)->default('web');
        });
    }

    public function down(): void
    {
        // Keep column — dropping would break verify-link platform routing.
    }
};
