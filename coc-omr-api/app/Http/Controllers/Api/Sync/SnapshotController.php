<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Services\ArchiveRetentionService;
use App\Services\SyncSnapshotService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SnapshotController extends Controller
{
    public function __construct(
        private readonly SyncSnapshotService $snapshotService,
        private readonly ArchiveRetentionService $archiveRetention,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        // Opportunistic purge (Render free often has no cron scheduler).
        $this->archiveRetention->purgeExpired($request->user()->id);

        $snapshot = $this->snapshotService->buildForTeacher($request->user());

        return response()->json([
            'sections' => $snapshot['sections'],
            'students' => $snapshot['students'],
            'subjects' => $snapshot['subjects'],
            'scan_results' => $snapshot['scan_results'],
            'deadlines' => $snapshot['deadlines'],
            'archive_retention_months' => ArchiveRetentionService::retentionMonths(),
        ]);
    }
}
