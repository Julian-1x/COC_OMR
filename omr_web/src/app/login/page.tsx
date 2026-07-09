"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import { isApiConfigured } from "@/lib/api/env";
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
  const [resendLoading, setResendLoading] = useState(false);
  const [awaitingConfirmation, setAwaitingConfirmation] = useState(false);

  async function handleResendConfirmation() {
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail) {
      setError("Enter your email above first.");
      return;
    }

    setResendLoading(true);
    setError(null);
    setNotice(null);
    try {
      const response = await fetch("/api/auth/resend-verification", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: normalizedEmail }),
      });
      const payload = (await response.json()) as { error?: string; message?: string };
      if (!response.ok || payload.error) {
        throw new Error(payload.error ?? "Could not resend confirmation email.");
      }
      setNotice(
        payload.message ??
          "Confirmation email sent. Check your inbox and spam folder, then tap the link.",
      );
      setAwaitingConfirmation(true);
      setMode("login");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not resend confirmation email.");
    } finally {
      setResendLoading(false);
    }
  }

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
      return;
    }

    if (searchParams.get("reset") === "1") {
      setNotice("Password updated. Sign in with your new password.");
      setMode("login");
    }
  }, [searchParams]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    setLoading(true);

    try {
      if (!isApiConfigured()) {
        throw new Error(
          "API URL missing. Check omr_web/.env.local and restart npm run dev.",
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
        message?: string;
      };
      if (!response.ok || payload.error) {
        throw new Error(payload.error ?? "Sign in failed.");
      }

      if (mode === "register" && payload.needsEmailConfirmation) {
        setAwaitingConfirmation(true);
        setNotice(
          payload.message ??
            "Account created. Open the confirmation email on this device, tap the link, and you will return here signed in.",
        );
        setMode("login");
        return;
      }

      router.push("/dashboard");
      router.refresh();
    } catch (err) {
      const message = err instanceof Error ? err.message : "Sign in failed.";
      if (message.toLowerCase().includes("already been taken") ||
          message.toLowerCase().includes("already exists")) {
        setAwaitingConfirmation(true);
        setError(
          "This email is already registered. Tap Resend confirmation below, or sign in if you already confirmed.",
        );
      } else if (
        message.toLowerCase().includes("not confirmed") ||
        message.toLowerCase().includes("not verified")
      ) {
        setAwaitingConfirmation(true);
        setError(
          "This email is not confirmed yet. Tap Resend confirmation below, then open the link in your inbox.",
        );
      } else if (message.toLowerCase().includes("failed to fetch")) {
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
            <div className="mb-1 flex items-center justify-between">
              <Label htmlFor="password">Password</Label>
              {mode === "login" ? (
                <Link
                  href="/auth/forgot-password"
                  className="text-xs font-semibold text-emerald-700 hover:underline"
                >
                  Forgot password?
                </Link>
              ) : null}
            </div>
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

          {awaitingConfirmation ? (
            <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-3 py-3 text-sm text-amber-950">
              <p className="font-bold">Waiting for email confirmation</p>
              <p className="mt-1">
                We sent a link to{" "}
                <span className="font-semibold">{email.trim() || "your email"}</span>.
                Check inbox and spam, or resend below.
              </p>
            </div>
          ) : null}

          {notice ? (
            <p className="mb-3 rounded-xl bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800">
              {notice}
            </p>
          ) : null}

          {error ? (
            <p className="mb-3 rounded-xl bg-red-50 px-3 py-2 text-sm font-semibold text-red-700">{error}</p>
          ) : null}

          <Button type="submit" className="w-full" disabled={loading || resendLoading}>
            {loading ? "Please wait…" : mode === "register" ? "Create account" : "Sign in"}
          </Button>

          {awaitingConfirmation ? (
            <Button
              type="button"
              variant="secondary"
              className="mt-3 w-full"
              disabled={loading || resendLoading}
              onClick={handleResendConfirmation}
            >
              {resendLoading ? "Sending…" : "Resend confirmation email"}
            </Button>
          ) : (
            <p className="mt-4 text-center text-sm text-slate-600">
              <button
                type="button"
                onClick={() => {
                  setAwaitingConfirmation(true);
                  void handleResendConfirmation();
                }}
                disabled={loading || resendLoading}
                className="font-semibold text-emerald-700 hover:underline disabled:opacity-60"
              >
                {resendLoading ? "Sending…" : "Resend confirmation email"}
              </button>
            </p>
          )}
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
