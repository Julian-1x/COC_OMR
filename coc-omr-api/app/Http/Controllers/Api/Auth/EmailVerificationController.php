<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Auth\Events\Verified;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

class EmailVerificationController extends Controller
{
    public function verify(Request $request, string $id, string $hash): JsonResponse|RedirectResponse
    {
        $user = User::query()->findOrFail($id);

        if (! hash_equals(sha1($user->getEmailForVerification()), (string) $hash)) {
            return $this->finish($request, false, 'Invalid verification link.');
        }

        if ($user->hasVerifiedEmail()) {
            return $this->finish($request, true, 'Email already verified.', $user);
        }

        if ($user->markEmailAsVerified()) {
            event(new Verified($user));
        }

        return $this->finish($request, true, 'Email verified.', $user);
    }

    public function resend(Request $request): JsonResponse
    {
        if ($request->user()->hasVerifiedEmail()) {
            return response()->json([
                'message' => 'Email already verified.',
            ]);
        }

        $request->user()->sendEmailVerificationNotification();

        return response()->json([
            'message' => 'Verification link sent.',
        ]);
    }

    private function finish(
        Request $request,
        bool $success,
        string $message,
        ?User $user = null,
    ): JsonResponse|RedirectResponse {
        if ($request->expectsJson() && ! $request->boolean('redirect')) {
            return response()->json([
                'message' => $message,
                'verified' => $success,
            ], $success ? 200 : 400);
        }

        $platform = $request->query('platform', 'web');
        $token = null;

        if ($success && $user !== null) {
            $user->loadMissing('teacherProfile');
        }

        if ($success && $user !== null && $user->isAccessApproved()) {
            $token = $user->createToken('email-verify')->plainTextToken;
        }

        $accessStatus = $user?->teacherProfile?->access_status;
        $accessPending = $success
            && $user !== null
            && ! $user->isAccessApproved();

        if ($platform === 'mobile') {
            $base = rtrim(config('app.mobile_verify_redirect'), '/');
            $query = http_build_query(array_filter([
                'token' => $token,
                'verified' => $success ? '1' : '0',
                'message' => $message,
                'access_status' => $accessStatus,
                'access_pending' => $accessPending ? '1' : null,
            ], fn ($value) => $value !== null && $value !== ''));

            return redirect()->away("{$base}?{$query}");
        }

        $frontend = rtrim(config('app.frontend_url'), '/');
        $query = http_build_query(array_filter([
            'token' => $token,
            'verified' => $success ? '1' : '0',
            'message' => $message,
            'access_status' => $accessStatus,
            'access_pending' => $accessPending ? '1' : null,
        ], fn ($value) => $value !== null && $value !== ''));

        return redirect()->away("{$frontend}/auth/callback?{$query}");
    }
}
