<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Services\AdminBootstrap;
use App\Support\CocSchool;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:255'],
        ]);

        if (! Auth::attempt([
            'email' => strtolower($credentials['email']),
            'password' => $credentials['password'],
        ])) {
            throw ValidationException::withMessages([
                'email' => ['These credentials do not match our records.'],
            ]);
        }

        /** @var \App\Models\User $user */
        $user = Auth::user();
        $user->loadMissing('teacherProfile');

        // Free-plan bootstrap: listed emails become super_admin without Render Shell.
        if (AdminBootstrap::promoteIfListed($user)) {
            $user->load('teacherProfile');
        }

        $profile = $user->teacherProfile;
        $accessStatus = $profile?->access_status ?? CocSchool::ACCESS_PENDING;

        if ($accessStatus === CocSchool::ACCESS_REVOKED || ($profile && ! $profile->is_active && $accessStatus !== CocSchool::ACCESS_PENDING)) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['This account was revoked by your school admin. Contact your COC admin if you need access again.'],
            ]);
        }

        if ($accessStatus !== CocSchool::ACCESS_APPROVED || ! ($profile?->is_active ?? false)) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['Your account is waiting for school admin approval. Ask your COC admin to approve you before signing in.'],
            ]);
        }

        if (! config('app.auto_verify_email') && ! $user->hasVerifiedEmail()) {
            Auth::logout();

            throw ValidationException::withMessages([
                'email' => ['This email has not been confirmed yet. Open the confirmation email, then sign in again.'],
            ]);
        }

        $deviceName = $credentials['device_name'] ?? 'mobile';
        $token = $user->createToken($deviceName)->plainTextToken;

        return response()->json([
            'user' => RegisterController::userPayload($user),
            'token' => $token,
            'token_type' => 'Bearer',
            'access_status' => CocSchool::ACCESS_APPROVED,
        ]);
    }
}
