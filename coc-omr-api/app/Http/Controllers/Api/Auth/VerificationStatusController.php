<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Lets an open register/login screen discover that email was verified
 * (e.g. user tapped the link in their mail app). Does not reveal whether
 * an unverified email is registered.
 */
class VerificationStatusController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email'],
        ]);

        $email = strtolower($request->string('email')->toString());
        $user = User::query()->where('email', $email)->with('teacherProfile')->first();
        $verified = $user !== null && $user->hasVerifiedEmail();

        if (! $verified) {
            return response()->json([
                'verified' => false,
                'access_pending' => false,
            ]);
        }

        $status = $user->teacherProfile?->access_status ?? CocSchool::ACCESS_PENDING;
        $approved = $user->isAccessApproved();

        return response()->json([
            'verified' => true,
            'access_pending' => ! $approved,
            'access_status' => $status,
        ]);
    }
}
