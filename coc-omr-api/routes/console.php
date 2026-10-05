<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Render free tier may not run cron reliably — SnapshotController also purges
// opportunistically. Keep the schedule for hosts that do run the scheduler.
Schedule::command('omr:purge-expired-archives')->daily();
