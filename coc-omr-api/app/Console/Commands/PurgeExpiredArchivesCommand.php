<?php

namespace App\Console\Commands;

use App\Services\ArchiveRetentionService;
use Illuminate\Console\Command;

class PurgeExpiredArchivesCommand extends Command
{
    protected $signature = 'omr:purge-expired-archives';

    protected $description = 'Permanently delete sections/students archived longer than the retention window';

    public function handle(ArchiveRetentionService $retention): int
    {
        $months = ArchiveRetentionService::retentionMonths();
        $this->info("Purging archives older than {$months} month(s)…");

        $summary = $retention->purgeExpired();

        $this->info(
            "Deleted {$summary['sections']} section(s), "
            ."{$summary['students']} student(s), "
            ."{$summary['scan_results']} scan result(s), "
            ."{$summary['deadlines']} deadline(s).",
        );

        return self::SUCCESS;
    }
}
