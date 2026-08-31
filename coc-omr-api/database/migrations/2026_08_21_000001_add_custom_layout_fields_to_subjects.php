<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subjects', function (Blueprint $table) {
            $table->boolean('use_custom_layout')->default(false)->after('use_partial_credit');
            $table->unsignedTinyInteger('options_count')->default(5)->after('use_custom_layout');
            $table->string('layout_shape', 32)->default('compact')->after('options_count');
        });
    }

    public function down(): void
    {
        Schema::table('subjects', function (Blueprint $table) {
            $table->dropColumn(['use_custom_layout', 'options_count', 'layout_shape']);
        });
    }
};
