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
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

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

        Gate::policy(Section::class, SectionPolicy::class);
        Gate::policy(Student::class, StudentPolicy::class);
        Gate::policy(Subject::class, SubjectPolicy::class);
        Gate::policy(ScanResult::class, ScanResultPolicy::class);
        Gate::policy(Deadline::class, DeadlinePolicy::class);
    }
}
