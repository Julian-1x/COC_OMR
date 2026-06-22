"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import { isSupabaseConfigured } from "@/lib/supabase/client";
import { workspaceName } from "@/lib/theme";

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [school, setSchool] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const authError = searchParams.get("error");
    if (authError === "confirm") {
      setNotice(
        "Your email may already be confirmed. Sign in below with the same email and password.",
      );
      setMode("login");
      return;
    }

    if (searchParams.get("confirmed") === "1") {
      setNotice("Email confirmed. Sign in to open your dashboard.");
      setMode("login");
    }
  }, [searchParams]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    setLoading(true);

    try {
      if (!isSupabaseConfigured()) {
        throw new Error(
          "Supabase keys missing. Check omr_web/.env.local and restart npm run dev.",
        );
      }

      const response = await fetch("/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode,
          email,
          password,
          name,
          school,
        }),
      });

      const payload = (await response.json()) as {
        error?: string;
        ok?: boolean;
        needsEmailConfirmation?: boolean;
      };
      if (!response.ok || payload.error) {
        throw new Error(payload.error ?? "Sign in failed.");
      }

      if (mode === "register" && payload.needsEmailConfirmation) {
        setNotice(
          "Account created. Open the confirmation email on this device, tap the link, and you will return here signed in.",
        );
        setMode("login");
        return;
      }

      router.push("/dashboard");
      router.refresh();
    } catch (err) {
      const message = err instanceof Error ? err.message : "Sign in failed.";
      if (message.toLowerCase().includes("failed to fetch")) {
        setError(
          "Could not reach the server. Make sure npm run dev is running, then try again.",
        );
      } else {
        setError(message);
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-slate-50">
      <div className="bg-gradient-to-br from-emerald-900 via-emerald-700 to-emerald-500 px-6 py-10 text-white">
        <div className="mx-auto max-w-md">
          <BrandHeader subtitle={`${workspaceName} · Web portal`} />
          <h1 className="mt-6 text-2xl font-extrabold">Teacher sign in</h1>
          <p className="mt-2 text-sm text-emerald-50/90">
            Use the same email and password as the mobile app. Scanning stays on your phone.
          </p>
        </div>
      </div>

      <div className="mx-auto -mt-8 max-w-md px-4 pb-10">
        <form
          onSubmit={handleSubmit}
          className="rounded-2xl border border-slate-200 bg-white p-6 shadow-lg"
        >
          <div className="mb-4 flex gap-2 rounded-xl bg-slate-100 p-1">
            {(["login", "register"] as const).map((item) => (
              <button
                key={item}
                type="button"
                onClick={() => setMode(item)}
                className={`flex-1 rounded-lg py-2 text-sm font-bold capitalize ${
                  mode === item ? "bg-white text-emerald-800 shadow" : "text-slate-500"
                }`}
              >
                {item}
              </button>
            ))}
          </div>

          {mode === "register" ? (
            <>
              <div className="mb-3">
                <Label htmlFor="name">Full name</Label>
                <Input id="name" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
              <div className="mb-3">
                <Label htmlFor="school">School / department</Label>
                <Input id="school" value={school} onChange={(e) => setSchool(e.target.value)} required />
              </div>
            </>
          ) : null}

          <div className="mb-3">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div className="mb-4">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              autoComplete={mode === "register" ? "new-password" : "current-password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              minLength={6}
              required
            />
          </div>

          {notice ? (
            <p className="mb-3 rounded-xl bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800">
              {notice}
            </p>
          ) : null}

          {error ? (
            <p className="mb-3 rounded-xl bg-red-50 px-3 py-2 text-sm font-semibold text-red-700">{error}</p>
          ) : null}

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Please wait…" : mode === "register" ? "Create account" : "Sign in"}
          </Button>
        </form>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-slate-50" />}>
      <LoginForm />
    </Suspense>
  );
}
