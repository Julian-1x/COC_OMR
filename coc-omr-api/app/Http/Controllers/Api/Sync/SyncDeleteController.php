<?php

namespace App\Http\Controllers\Api\Sync;

use App\Http\Controllers\Controller;
use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\Subject;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SyncDeleteController extends Controller
{
    /** @var array<string, class-string<Model>> */
    private const TABLE_MAP = [
        'sections' => Section::class,
        'students' => Student::class,
        'subjects' => Subject::class,
        'scan_results' => ScanResult::class,
        'scan-results' => ScanResult::class,
        'deadlines' => Deadline::class,
    ];

    public function destroy(Request $request, string $table, string $id): JsonResponse
    {
        $modelClass = self::TABLE_MAP[$table] ?? null;

        if ($modelClass === null) {
            return response()->json([
                'message' => 'Unknown sync table.',
            ], 404);
        }

        /** @var Model|null $record */
        $record = $modelClass::query()->find($id);

        if ($record === null) {
            return response()->json([
                'message' => 'Record not found.',
            ], 404);
        }

        $this->authorize('delete', $record);
        $record->delete();

        return response()->json([
            'message' => 'Deleted.',
            'id' => $id,
        ]);
    }
}
