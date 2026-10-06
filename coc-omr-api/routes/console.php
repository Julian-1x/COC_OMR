<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Daily purge of archives past retention. Do not run this from /sync/snapshot —
// sync must stay a read path. Portal Archived list still purges opportunistically.
Schedule::command('omr:purge-expired-archives')->daily();
