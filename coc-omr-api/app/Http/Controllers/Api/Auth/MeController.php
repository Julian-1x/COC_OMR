<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MeController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $user = $request->user();
        $user->loadMissing('teacherProfile');

        return response()->json([
            'user' => RegisterController::userPayload($user),
            'access_status' => $user->teacherProfile?->access_status,
        ]);
    }
}
