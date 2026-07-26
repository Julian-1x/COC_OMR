<?php

use App\Support\CocSchool;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('teacher_profiles', function (Blueprint $table) {
            $table->string('access_status', 32)
                ->default(CocSchool::ACCESS_PENDING)
                ->after('is_active');
        });

        // Existing teachers keep working after deploy.
        DB::table('teacher_profiles')->update([
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);
    }

    public function down(): void
    {
        Schema::table('teacher_profiles', function (Blueprint $table) {
            $table->dropColumn('access_status');
        });
    }
};
