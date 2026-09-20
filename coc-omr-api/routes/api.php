<?php

use App\Http\Controllers\Api\AppReleaseController;
use App\Http\Controllers\Api\Auth\EmailVerificationController;
use App\Http\Controllers\Api\Auth\ForgotPasswordController;
use App\Http\Controllers\Api\Auth\LoginController;
use App\Http\Controllers\Api\Auth\LogoutController;
use App\Http\Controllers\Api\Auth\MeController;
use App\Http\Controllers\Api\Auth\MfaChallengeController;
use App\Http\Controllers\Api\Auth\MfaEnrollController;
use App\Http\Controllers\Api\Auth\RegisterController;
use App\Http\Controllers\Api\Auth\ResendVerificationController;
use App\Http\Controllers\Api\Auth\ResetPasswordController;
use App\Http\Controllers\Api\Auth\SecurityConfigController;
use App\Http\Controllers\Api\Auth\VerificationStatusController;
use App\Http\Controllers\Api\MailDiagnosticsController;
use App\Http\Controllers\Api\PinController;
use App\Http\Controllers\Api\Portal\AdminController;
use App\Http\Controllers\Api\Portal\AuthEventsController;
use App\Http\Controllers\Api\Portal\DashboardController;
use App\Http\Controllers\Api\Portal\ScanResultController;
use App\Http\Controllers\Api\Portal\SectionController;
use App\Http\Controllers\Api\Portal\StudentController;
use App\Http\Controllers\Api\Portal\SubjectController;
use App\Http\Controllers\Api\Sync\DeadlineSyncController;
use App\Http\Controllers\Api\Sync\ScanResultSyncController;
use App\Http\Controllers\Api\Sync\SectionSyncController;
use App\Http\Controllers\Api\Sync\SnapshotController;
use App\Http\Controllers\Api\Sync\StudentSyncController;
use App\Http\Controllers\Api\Sync\SubjectSyncController;
use App\Http\Controllers\Api\Sync\SyncDeleteController;
use Illuminate\Support\Facades\Route;

Route::prefix('register')->group(function () {
    Route::post('/', RegisterController::class)->middleware('throttle:register-ip');
});

Route::get('/auth/security-config', SecurityConfigController::class);

Route::post('/login', LoginController::class)
    ->middleware(['throttle:login-ip', 'throttle:login-email']);
Route::post('/login/mfa', MfaChallengeController::class)
    ->middleware(['throttle:login-ip', 'throttle:login-email']);
Route::post('/login/mfa/setup', [MfaEnrollController::class, 'setupDuringLogin'])
    ->middleware(['throttle:login-ip', 'throttle:login-email']);
Route::post('/login/mfa/enroll', [MfaEnrollController::class, 'enrollDuringLogin'])
    ->middleware(['throttle:login-ip', 'throttle:login-email']);

Route::post('/forgot-password', ForgotPasswordController::class)
    ->middleware('throttle:6,1');
Route::post('/reset-password', ResetPasswordController::class);
Route::post('/email/resend-verification', ResendVerificationController::class)
    ->middleware('throttle:6,1');
Route::post('/email/verification-check', VerificationStatusController::class)
    ->middleware('throttle:60,1');

Route::get('/email/verify/{id}/{hash}', [EmailVerificationController::class, 'verify'])
    ->middleware(['signed', 'throttle:6,1'])
    ->name('verification.verify');

Route::get('/health/mail-config', [MailDiagnosticsController::class, 'config']);
Route::post('/health/mail-test', [MailDiagnosticsController::class, 'sendTest'])
    ->middleware('throttle:6,1');

// TEMPORARY diagnostic: separates DB connection handshake cost from query cost.
// Reports timings only (no rows, no credentials). Remove after slowness is fixed.
Route::get('/health/db-latency', static function () {
    $url = (string) config('database.connections.pgsql.url');
    $host = parse_url($url, PHP_URL_HOST) ?: (string) config('database.connections.pgsql.host');
    $parts = explode('.', $host);
    if (count($parts) > 2) {
        $parts[0] = '***';
    }

    \Illuminate\Support\Facades\DB::disconnect();

    $t = microtime(true);
    \Illuminate\Support\Facades\DB::connection()->getPdo();
    $connectMs = (microtime(true) - $t) * 1000;

    $t = microtime(true);
    \Illuminate\Support\Facades\DB::select('select 1');
    $firstQueryMs = (microtime(true) - $t) * 1000;

    $t = microtime(true);
    for ($i = 0; $i < 5; $i++) {
        \Illuminate\Support\Facades\DB::select('select 1');
    }
    $fiveQueriesMs = (microtime(true) - $t) * 1000;

    $t = microtime(true);
    \Illuminate\Support\Facades\DB::table('users')->count();
    $userCountMs = (microtime(true) - $t) * 1000;

    return response()->json([
        'db_host_masked' => implode('.', $parts),
        'connect_ms' => round($connectMs, 1),
        'first_query_ms' => round($firstQueryMs, 1),
        'five_queries_ms' => round($fiveQueriesMs, 1),
        'per_query_ms' => round($fiveQueriesMs / 5, 1),
        'user_count_query_ms' => round($userCountMs, 1),
        'build_commit' => substr((string) env('RENDER_GIT_COMMIT', 'unknown'), 0, 7),
    ]);
})->middleware('throttle:30,1');

Route::middleware(['auth:sanctum', 'verified', 'teacher.approved'])->group(function () {
    Route::post('/logout', LogoutController::class);
    Route::get('/me', MeController::class);

    Route::prefix('mfa')->group(function () {
        Route::post('/setup', [MfaEnrollController::class, 'setup']);
        Route::post('/confirm', [MfaEnrollController::class, 'confirm']);
        Route::post('/disable', [MfaEnrollController::class, 'disable']);
    });

    Route::post('/email/verification-notification', [EmailVerificationController::class, 'resend'])
        ->middleware('throttle:6,1');

    Route::get('/sync/snapshot', SnapshotController::class);
    Route::post('/sync/sections', [SectionSyncController::class, 'store']);
    Route::patch('/sync/sections/archive', [SectionSyncController::class, 'archive']);
    Route::patch('/sync/sections/unarchive', [SectionSyncController::class, 'unarchive']);
    Route::post('/sync/students', [StudentSyncController::class, 'store']);
    Route::patch('/sync/students/archive', [StudentSyncController::class, 'archive']);
    Route::patch('/sync/students/unarchive', [StudentSyncController::class, 'unarchive']);
    Route::post('/sync/subjects', [SubjectSyncController::class, 'store']);
    Route::post('/sync/scan-results', [ScanResultSyncController::class, 'store']);
    Route::post('/sync/deadlines', [DeadlineSyncController::class, 'store']);
    Route::delete('/sync/{table}/{id}', [SyncDeleteController::class, 'destroy']);

    Route::get('/profile/pin', [PinController::class, 'show']);
    Route::put('/profile/pin', [PinController::class, 'update']);

    Route::get('/app-releases/latest', [AppReleaseController::class, 'latest']);

    Route::get('/dashboard/stats', [DashboardController::class, 'stats']);
    Route::get('/dashboard/last-updated', [DashboardController::class, 'lastUpdated']);

    Route::get('/subjects/by-local/{localId}', [SubjectController::class, 'showByLocalId']);

    Route::apiResource('sections', SectionController::class);
    Route::apiResource('students', StudentController::class);
    Route::apiResource('subjects', SubjectController::class);
    Route::apiResource('scan-results', ScanResultController::class);

    Route::prefix('admin')->middleware('school.admin')->group(function () {
        Route::get('/stats', [AdminController::class, 'stats']);
        Route::get('/teachers', [AdminController::class, 'teachers']);
        Route::get('/access-requests', [AdminController::class, 'accessRequests']);
        Route::post('/teachers/{teacherId}/approve', [AdminController::class, 'approve']);
        Route::post('/teachers/{teacherId}/revoke', [AdminController::class, 'revoke']);
        Route::get('/teachers/{teacherId}', [AdminController::class, 'teacher']);
        Route::get('/teachers/{teacherId}/sections/{sectionName}/students', [AdminController::class, 'sectionStudents']);

        Route::middleware('super.admin')->group(function () {
            Route::get('/department-admins', [AdminController::class, 'departmentAdmins']);
            Route::get('/auth-events', [AuthEventsController::class, 'index']);
            Route::post('/teachers/{teacherId}/make-dept-admin', [AdminController::class, 'makeDeptAdmin']);
            Route::post('/teachers/{teacherId}/revoke-dept-admin', [AdminController::class, 'revokeDeptAdmin']);
            Route::delete('/teachers/{teacherId}', [AdminController::class, 'destroy']);
        });
    });
});
