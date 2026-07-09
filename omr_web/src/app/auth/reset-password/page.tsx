"use client";

import Link from "next/link";
import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import { isApiConfigured } from "@/lib/api/env";
import { workspaceName } from "@/lib/theme";

function ResetPasswordForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [email, setEmail] = useState("");
  const [token, setToken] = useState("");
  const [password, setPassword] = useState("");
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [linkInvalid, setLinkInvalid] = useState(false);

  useEffect(() => {
    const urlToken = searchParams.get("token")?.trim() ?? "";
    const urlEmail = searchParams.get("email")?.trim().toLowerCase() ?? "";
    setToken(urlToken);
    setEmail(urlEmail);
    if (!urlToken || !urlEmail) {
      setLinkInvalid(true);
      setError(
        "This reset link is incomplete or expired. Request a new link from Forgot password.",
      );
    }
  }, [searchParams]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setNotice(null);

    if (password !== passwordConfirmation) {
      setError("Passwords do not match.");
      return;
    }
    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }

    setLoading(true);
    try {
      if (!isApiConfigured()) {
        throw new Error("API URL missing. Contact your administrator.");
      }

      const response = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          token,
          password,
          password_confirmation: passwordConfirmation,
        }),
      });

      const payload = (await response.json()) as { error?: string; ok?: boolean };
      if (!response.ok || payload.error) {
        throw new Error(payload.error ?? "Password reset failed.");
      }

      setNotice(
        "Password updated. You can now sign in on the phone app or web with your new password.",
      );
      setTimeout(() => router.push("/login?reset=1"), 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Request failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-slate-50">
      <div className="bg-gradient-to-br from-emerald-900 via-emerald-700 to-emerald-500 px-6 py-10 text-white">
        <div className="mx-auto max-w-md">
          <BrandHeader subtitle={`${workspaceName} · New password`} />
          <h1 className="mt-6 text-2xl font-extrabold">Set a new password</h1>
          <p className="mt-2 text-sm text-emerald-50/90">
            Choose a strong password you will use on the mobile app and this web portal.
          </p>
        </div>
      </div>

      <div className="mx-auto -mt-8 max-w-md px-4 pb-10">
        <form
          onSubmit={handleSubmit}
          className="rounded-2xl border border-slate-200 bg-white p-6 shadow-lg"
        >
          <div className="mb-3">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              readOnly={Boolean(searchParams.get("email"))}
              required
            />
          </div>

          <div className="mb-3">
            <Label htmlFor="password">New password</Label>
            <Input
              id="password"
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              minLength={8}
              required
              disabled={linkInvalid}
            />
          </div>

          <div className="mb-4">
            <Label htmlFor="password_confirmation">Confirm new password</Label>
            <Input
              id="password_confirmation"
              type="password"
              autoComplete="new-password"
              value={passwordConfirmation}
              onChange={(e) => setPasswordConfirmation(e.target.value)}
              minLength={8}
              required
              disabled={linkInvalid}
            />
          </div>

          {notice ? (
            <p className="mb-3 rounded-xl bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800">
              {notice}
            </p>
          ) : null}

          {error ? (
            <p className="mb-3 rounded-xl bg-red-50 px-3 py-2 text-sm font-semibold text-red-700">
              {error}
            </p>
          ) : null}

          <Button type="submit" className="w-full" disabled={loading || linkInvalid}>
            {loading ? "Saving…" : "Update password"}
          </Button>

          <p className="mt-4 text-center text-sm text-slate-600">
            <Link
              href="/auth/forgot-password"
              className="font-semibold text-emerald-700 hover:underline"
            >
              Request a new reset link
            </Link>
            {" · "}
            <Link href="/login" className="font-semibold text-emerald-700 hover:underline">
              Sign in
            </Link>
          </p>
        </form>
      </div>
    </div>
  );
}

export default function ResetPasswordPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-slate-50" />}>
      <ResetPasswordForm />
    </Suspense>
  );
}
