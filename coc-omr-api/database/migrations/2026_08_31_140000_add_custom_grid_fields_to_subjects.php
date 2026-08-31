<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subjects', function (Blueprint $table) {
            $table->string('custom_layout_id', 64)->nullable()->after('layout_shape');
            $table->unsignedTinyInteger('custom_grid_columns')->nullable()->after('custom_layout_id');
            $table->unsignedTinyInteger('custom_grid_rows')->nullable()->after('custom_grid_columns');
        });
    }

    public function down(): void
    {
        Schema::table('subjects', function (Blueprint $table) {
            $table->dropColumn([
                'custom_layout_id',
                'custom_grid_columns',
                'custom_grid_rows',
            ]);
        });
    }
};
