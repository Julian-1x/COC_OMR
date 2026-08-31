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
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;

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
    }
}
