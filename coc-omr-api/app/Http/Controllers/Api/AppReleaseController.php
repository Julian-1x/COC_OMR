<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppRelease;
use Illuminate\Http\JsonResponse;

class AppReleaseController extends Controller
{
    public function latest(): JsonResponse
    {
        $release = AppRelease::query()
            ->orderByDesc('build_number')
            ->first();

        if ($release === null) {
            return response()->json([
                'release' => null,
            ]);
        }

        return response()->json([
            'release' => [
                'build_number' => $release->build_number,
                'version_name' => $release->version_name,
                'download_url' => $release->download_url,
                'notes' => $release->notes,
                'mandatory' => $release->mandatory,
                'created_at' => $release->created_at,
            ],
        ]);
    }
}
