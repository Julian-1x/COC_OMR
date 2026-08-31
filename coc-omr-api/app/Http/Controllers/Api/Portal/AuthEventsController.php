<?php

namespace App\Http\Controllers\Api\Portal;

use App\Http\Controllers\Controller;
use App\Models\AuthEvent;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuthEventsController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'limit' => ['nullable', 'integer', 'min:1', 'max:200'],
            'event' => ['nullable', 'string', 'max:64'],
            'email' => ['nullable', 'string', 'max:255'],
        ]);

        $limit = $validated['limit'] ?? 50;

        $query = AuthEvent::query()->orderByDesc('created_at');

        if (! empty($validated['event'])) {
            $query->where('event', $validated['event']);
        }
        if (! empty($validated['email'])) {
            $query->where('email', 'like', '%'.strtolower($validated['email']).'%');
        }

        $events = $query->limit($limit)->get();

        return response()->json([
            'events' => $events,
        ]);
    }
}
