<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PinController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $profile = $request->user()->teacherProfile;

        if ($profile === null
            || empty($profile->pin_hash)
            || empty($profile->pin_salt)) {
            return response()->json([
                'pin_hash' => null,
                'pin_salt' => null,
                'full_name' => $profile?->full_name,
                'school_name' => $profile?->school_name,
            ]);
        }

        return response()->json([
            'pin_hash' => $profile->pin_hash,
            'pin_salt' => $profile->pin_salt,
            'full_name' => $profile->full_name,
            'school_name' => $profile->school_name,
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'pin_hash' => ['required', 'string', 'max:2048'],
            'pin_salt' => ['required', 'string', 'max:2048'],
        ]);

        $user = $request->user();
        $profile = $user->teacherProfile;

        if ($profile === null) {
            $profile = $user->teacherProfile()->updateOrCreate(
                ['id' => $user->id],
                [
                    'full_name' => $user->name,
                    'role' => 'teacher',
                    'is_active' => true,
                ],
            );
        }

        $profile->update([
            'pin_hash' => $validated['pin_hash'],
            'pin_salt' => $validated['pin_salt'],
        ]);

        return response()->json([
            'message' => 'PIN saved to cloud.',
        ]);
    }
}
