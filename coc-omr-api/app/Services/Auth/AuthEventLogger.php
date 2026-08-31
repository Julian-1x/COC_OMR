<?php

namespace App\Services\Auth;

use App\Models\AuthEvent;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

class AuthEventLogger
{
    public function record(
        string $event,
        string $email,
        ?User $user = null,
        ?Request $request = null,
        array $metadata = [],
    ): void {
        AuthEvent::query()->create([
            'user_id' => $user?->id,
            'email' => strtolower(trim($email)),
            'event' => $event,
            'ip_address' => $request?->ip(),
            'user_agent' => $request?->userAgent(),
            'metadata' => $metadata === [] ? null : $metadata,
        ]);
    }
}
