<?php

namespace App\Providers;

use App\Models\Deadline;
use App\Models\ScanResult;
use App\Models\Section;
use App\Models\Student;
use App\Models\Subject;
use App\Policies\DeadlinePolicy;
use App\Policies\ScanResultPolicy;
use App\Policies\SectionPolicy;
use App\Policies\StudentPolicy;
use App\Policies\SubjectPolicy;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Http\Request;
use Illuminate\Cache\RateLimiting\Limit;
use App\Services\TeacherApprovalBootstrap;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        $appUrl = (string) config('app.url');
        if ($appUrl !== '') {
            URL::forceRootUrl($appUrl);
        }
        if (str_starts_with($appUrl, 'https://')) {
            URL::forceScheme('https');
        }

        // Some Apache setups strip Authorization. Accept the same Sanctum
        // token from X-COC-Api-Token so Bearer auth still works for desk/mobile.
        Sanctum::getAccessTokenFromRequestUsing(static function (Request $request) {
            $bearer = $request->bearerToken();
            if (is_string($bearer) && str_contains($bearer, '|')) {
                return $bearer;
            }
            $alt = $request->header('X-COC-Api-Token');
            if (is_string($alt) && str_contains($alt, '|')) {
                return $alt;
            }

            return is_string($bearer) ? $bearer : '';
        });

        // Registration + password reset: 8+ chars with a letter, number, and symbol.
        Password::defaults(static function () {
            return Password::min(8)
                ->letters()
                ->numbers()
                ->symbols();
        });

        RateLimiter::for('login-ip', static function (Request $request) {
            return Limit::perMinute((int) config('security.login.ip_per_minute', 20))
                ->by($request->ip());
        });

        RateLimiter::for('login-email', static function (Request $request) {
            $email = strtolower((string) $request->input('email', ''));

            return Limit::perMinute((int) config('security.login.email_per_minute', 8))
                ->by(sha1($email.'|'.$request->ip()));
        });

        RateLimiter::for('register-ip', static function (Request $request) {
            return Limit::perMinute((int) config('security.register.ip_per_minute', 5))
                ->by($request->ip());
        });

        Gate::policy(Section::class, SectionPolicy::class);
        Gate::policy(Student::class, StudentPolicy::class);
        Gate::policy(Subject::class, SubjectPolicy::class);
        Gate::policy(ScanResult::class, ScanResultPolicy::class);
        Gate::policy(Deadline::class, DeadlinePolicy::class);

        try {
            $approved = TeacherApprovalBootstrap::approvePendingFromEnv();
            if ($approved > 0) {
                Log::info('COC teacher approval bootstrap applied on boot', [
                    'approved_count' => $approved,
                ]);
            }
        } catch (\Throwable $error) {
            // DB may not be ready during install/migrate; login hook still applies approvals.
            Log::debug('COC teacher approval bootstrap skipped on boot', [
                'error' => $error->getMessage(),
            ]);
        }
    }
}
