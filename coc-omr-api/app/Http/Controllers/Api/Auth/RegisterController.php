<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\TeacherProfile;
use App\Models\User;
use Illuminate\Auth\Events\Registered;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class RegisterController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'confirmed', Password::defaults()],
            'full_name' => ['required', 'string', 'max:255'],
            'school' => ['nullable', 'string', 'max:255'],
        ]);

        $user = User::query()->create([
            'name' => $validated['full_name'],
            'email' => strtolower($validated['email']),
            'password' => Hash::make($validated['password']),
        ]);

        TeacherProfile::query()->create([
            'id' => $user->id,
            'full_name' => $validated['full_name'],
            'school_name' => $validated['school'] ?? null,
            'role' => 'teacher',
            'is_active' => true,
        ]);

        if (config('app.auto_verify_email')) {
            $user->markEmailAsVerified();
        } else {
            event(new Registered($user));
        }

        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'user' => $this->userPayload($user),
            'token' => $token,
            'token_type' => 'Bearer',
        ], 201);
    }

    /**
     * @return array<string, mixed>
     */
    public static function userPayload(User $user): array
    {
        $user->loadMissing('teacherProfile');

        return [
            'id' => $user->id,
            'email' => $user->email,
            'email_verified_at' => $user->email_verified_at,
            'profile' => $user->teacherProfile,
        ];
    }
}
