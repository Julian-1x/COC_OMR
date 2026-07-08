<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Services\SyncSnapshotService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SnapshotController extends Controller
{
    public function __construct(
        private readonly SyncSnapshotService $snapshotService,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $snapshot = $this->snapshotService->buildForTeacher($request->user());

        return response()->json([
            'sections' => $snapshot['sections'],
            'students' => $snapshot['students'],
            'subjects' => $snapshot['subjects'],
            'scan_results' => $snapshot['scan_results'],
            'deadlines' => $snapshot['deadlines'],
        ]);
    }
}
