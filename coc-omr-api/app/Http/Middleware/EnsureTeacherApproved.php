<?php

namespace App\Http\Middleware;

use App\Support\CocSchool;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Blocks sync/dashboard for teachers who are pending or revoked.
 * Allows /api/me and /api/logout so clients can show a waiting screen.
 */
class EnsureTeacherApproved
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if ($user === null) {
            return $next($request);
        }

        $path = '/'.ltrim($request->path(), '/');
        // API routes are prefixed with /api
        $relative = preg_replace('#^api/#', '', ltrim($path, '/')) ?? '';
        $relative = '/'.ltrim($relative, '/');

        $allowedWhilePending = [
            '/me',
            '/logout',
        ];

        if (in_array($relative, $allowedWhilePending, true)) {
            return $next($request);
        }

        $profile = $user->teacherProfile;
        $status = $profile?->access_status ?? CocSchool::ACCESS_PENDING;

        if ($status === CocSchool::ACCESS_APPROVED && ($profile?->is_active ?? false)) {
            return $next($request);
        }

        $message = $status === CocSchool::ACCESS_REVOKED
            ? 'This account was revoked by your school admin. Contact your COC admin if you need access again.'
            : 'Your account is waiting for school admin approval. Ask your COC admin to approve you before using the app or web dashboard.';

        return response()->json([
            'message' => $message,
            'access_status' => $status,
        ], 403);
    }
}
