<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Lets the open web login tab discover that email was verified on another device.
 * Does not reveal whether the email is registered — only whether it is verified.
 */
class VerificationStatusController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email'],
        ]);

        $email = strtolower($request->string('email')->toString());
        $user = User::query()->where('email', $email)->first();

        return response()->json([
            'verified' => $user !== null && $user->hasVerifiedEmail(),
        ]);
    }
}
