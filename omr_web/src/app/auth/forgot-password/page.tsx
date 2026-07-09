"use client";

import Link from "next/link";
import { useState } from "react";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import { isApiConfigured } from "@/lib/api/env";
import { workspaceName } from "@/lib/theme";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    setLoading(true);

    try {
      if (!isApiConfigured()) {
        throw new Error("API URL missing. Contact your administrator.");
      }

      const response = await fetch("/api/auth/forgot-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });

      const payload = (await response.json()) as { error?: string; ok?: boolean };
      if (!response.ok || payload.error) {
        throw new Error(payload.error ?? "Could not send reset link.");
      }

      setNotice(
        "If that email is registered, a reset link is on its way. Open it on this device, set a new password, then sign in on the app or web.",
      );
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
          <BrandHeader subtitle={`${workspaceName} · Password help`} />
          <h1 className="mt-6 text-2xl font-extrabold">Forgot password</h1>
          <p className="mt-2 text-sm text-emerald-50/90">
            Enter your account email. We will send a link to set a new password.
          </p>
        </div>
      </div>

      <div className="mx-auto -mt-8 max-w-md px-4 pb-10">
        <form
          onSubmit={handleSubmit}
          className="rounded-2xl border border-slate-200 bg-white p-6 shadow-lg"
        >
          <div className="mb-4">
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

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Sending…" : "Send reset link"}
          </Button>

          <p className="mt-4 text-center text-sm text-slate-600">
            <Link href="/login" className="font-semibold text-emerald-700 hover:underline">
              Back to sign in
            </Link>
          </p>
        </form>
      </div>
    </div>
  );
}
