<?php

use App\Services\AdminBootstrap;
use Illuminate\Database\Migrations\Migration;

/**
 * Bootstrap the first COC school admin without Render Shell (free plan).
 * Safe to re-run: promote is idempotent if already school_admin.
 */
return new class extends Migration
{
    public function up(): void
    {
        AdminBootstrap::promoteEmailInDatabase('alex.balaba.coc@phinmaed.com');
    }

    public function down(): void
    {
        // Keep admin privileges if rolled back — demote only via omr:promote-admin --demote.
    }
};
