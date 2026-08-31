"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import { isApiConfigured } from "@/lib/api/env";
import { readJsonResponse } from "@/lib/api/read-json-response";
import { wakeSchoolApi } from "@/lib/api/wake-api";
import {
  PASSWORD_MIN_LENGTH,
  PASSWORD_REQUIREMENT_HINT,
  passwordValidationError,
} from "@/lib/auth/password-rules";
import { COC_DEPARTMENTS, COC_SCHOOL_NAME, isCocDepartment } from "@/lib/coc-school";
import { workspaceName } from "@/lib/theme";
import { TurnstileField } from "@/components/auth/turnstile-field";
import QRCode from "qrcode";

const CAPTCHA_SITE_KEY =
  process.env.NEXT_PUBLIC_CAPTCHA_SITE_KEY?.trim() ?? "";

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [lastName, setLastName] = useState("");
  const [firstName, setFirstName] = useState("");
  const [department, setDepartment] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [resendLoading, setResendLoading] = useState(false);
  const [awaitingConfirmation, setAwaitingConfirmation] = useState(false);
  const [awaitingApproval, setAwaitingApproval] = useState(false);
  const [awaitingMfa, setAwaitingMfa] = useState(false);
  const [awaitingMfaEnrollment, setAwaitingMfaEnrollment] = useState(false);
  const [mfaTicket, setMfaTicket] = useState<string | null>(null);
  const [mfaCode, setMfaCode] = useState("");
  const [mfaSetupSecret, setMfaSetupSecret] = useState<string | null>(null);
  const [mfaOtpAuthUrl, setMfaOtpAuthUrl] = useState<string | null>(null);
  const [mfaQrDataUrl, setMfaQrDataUrl] = useState<string | null>(null);
  const [mfaSetupView, setMfaSetupView] = useState<"qr" | "secret">("qr");
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [captchaSiteKey, setCaptchaSiteKey] = useState(CAPTCHA_SITE_KEY);
  const [slowServerHint, setSlowServerHint] = useState(false);
  const autoSignInInFlight = useRef(false);
  const loadingRef = useRef(false);

  useEffect(() => {
    loadingRef.current = loading;
  }, [loading]);

  useEffect(() => {
    if (!isApiConfigured()) {
      return;
    }
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL?.trim();
    if (!apiBase) {
      return;
    }
    void wakeSchoolApi(apiBase, { attempts: 2, delayMs: 1500 });
  }, []);

  useEffect(() => {
    if (!loading) {
      setSlowServerHint(false);
      return;
    }
    const timer = window.setTimeout(() => {
      setSlowServerHint(true);
    }, 4000);
    return () => window.clearTimeout(timer);
  }, [loading]);

  const signInWithPassword = useCallback(
    async (signInEmail: string, signInPassword: string) => {
      const response = await fetch("/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode: "login",
          email: signInEmail,
          password: signInPassword,
        }),
      });

      const payload = await readJsonResponse<{
        error?: string;
        ok?: boolean;
        needsEmailConfirmation?: boolean;
        accessPending?: boolean;
        message?: string;
      }>(response);
      if (!response.ok || payload.error) {
        if (payload.accessPending || payload.error?.toLowerCase().includes("admin approval")) {
          const err = new Error(payload.error ?? "Waiting for school admin approval.");
          (err as Error & { accessPending?: boolean }).accessPending = true;
          throw err;
        }
        throw new Error(payload.error ?? "Sign in failed.");
      }

      router.push("/dashboard");
      router.refresh();
    },
    [router],
  );

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
      const payload = await readJsonResponse<{ error?: string; message?: string }>(
        response,
      );
      if (!response.ok || payload.error) {
        throw new Error(payload.error ?? "Could not resend confirmation email.");
      }
      setNotice(
        payload.message ??
          "Confirmation email sent. Check your inbox and spam folder, then tap Verify email (web).",
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

    if (searchParams.get("pending") === "1") {
      setAwaitingApproval(true);
      setAwaitingConfirmation(false);
      setMode("login");
      setNotice(
        searchParams.get("confirmed") === "1"
          ? "Email confirmed. Your account is waiting for a COC admin to approve access."
          : "Your account is waiting for a COC admin to approve access.",
      );
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

  // While waiting for email confirmation, poll so verifying on phone unlocks this tab.
  useEffect(() => {
    if (!awaitingConfirmation) {
      return;
    }

    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail || !password) {
      return;
    }

    let cancelled = false;
    let consecutiveFailures = 0;

    const checkAndSignIn = async () => {
      if (cancelled || autoSignInInFlight.current || loadingRef.current) {
        return;
      }

      try {
        const response = await fetch("/api/auth/verification-status", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email: normalizedEmail }),
        });
        const payload = (await response.json()) as {
          verified?: boolean;
          error?: string;
        };
        if (!response.ok) {
          consecutiveFailures += 1;
          return;
        }
        consecutiveFailures = 0;
        if (!payload.verified || cancelled) {
          return;
        }

        autoSignInInFlight.current = true;
        setNotice("Email confirmed — signing you in…");
        setError(null);
        setLoading(true);
        try {
          await signInWithPassword(normalizedEmail, password);
          setAwaitingConfirmation(false);
        } catch (err) {
          const message = err instanceof Error ? err.message : "Sign in failed.";
          const accessPending =
            (err as Error & { accessPending?: boolean }).accessPending === true ||
            message.toLowerCase().includes("admin approval") ||
            message.toLowerCase().includes("waiting for school admin");
          if (accessPending) {
            setAwaitingConfirmation(false);
            setAwaitingApproval(true);
            setNotice(
              "Email confirmed. Ask your COC admin to approve your account, then sign in again.",
            );
          } else if (
            message.toLowerCase().includes("not confirmed") ||
            message.toLowerCase().includes("not verified")
          ) {
            setAwaitingConfirmation(true);
            setNotice("Almost there — waiting for confirmation to finish syncing.");
          } else {
            setAwaitingConfirmation(false);
            setError(
              "Email is confirmed. Enter your password and tap Sign in to continue.",
            );
            setNotice("Email confirmed. Sign in below.");
          }
        } finally {
          setLoading(false);
          autoSignInInFlight.current = false;
        }
      } catch {
        consecutiveFailures += 1;
        if (consecutiveFailures > 20) {
          // Stop hammering if the API is unreachable for a long stretch.
          cancelled = true;
        }
      }
    };

    void checkAndSignIn();
    const intervalId = window.setInterval(() => {
      void checkAndSignIn();
    }, 4000);

    const timeoutId = window.setTimeout(() => {
      cancelled = true;
      window.clearInterval(intervalId);
    }, 15 * 60 * 1000);

    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
      window.clearTimeout(timeoutId);
    };
  }, [awaitingConfirmation, email, password, signInWithPassword]);

  useEffect(() => {
    if (!awaitingMfaEnrollment || !mfaTicket) {
      return;
    }

    let cancelled = false;

    async function loadSetup() {
      try {
        const response = await fetch("/auth/login/mfa-setup", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ mfa_ticket: mfaTicket }),
        });
        const payload = await readJsonResponse<{
          error?: string;
          secret?: string;
          otpauthUrl?: string;
        }>(response);
        if (!response.ok || !payload.secret) {
          throw new Error(payload.error ?? "Could not start two-factor setup.");
        }
        if (!cancelled) {
          setMfaSetupSecret(payload.secret);
          setMfaOtpAuthUrl(payload.otpauthUrl ?? null);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Could not start two-factor setup.");
        }
      }
    }

    void loadSetup();

    return () => {
      cancelled = true;
    };
  }, [awaitingMfaEnrollment, mfaTicket]);

  useEffect(() => {
    if (!mfaOtpAuthUrl) {
      setMfaQrDataUrl(null);
      return;
    }
    let cancelled = false;
    QRCode.toDataURL(mfaOtpAuthUrl, { width: 220, margin: 2 })
      .then((url) => {
        if (!cancelled) {
          setMfaQrDataUrl(url);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setMfaQrDataUrl(null);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [mfaOtpAuthUrl]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    setLoading(true);
    setSlowServerHint(awaitingMfa);

    try {
      if (!isApiConfigured()) {
        throw new Error(
          "API URL missing. Check omr_web/.env.local and restart npm run dev.",
        );
      }

      if (awaitingMfaEnrollment && !mfaSetupSecret) {
        throw new Error(
          "Setup key is still loading. Wait until it appears, add it to your authenticator app, then enter the code.",
        );
      }

      if (mode === "register" && !isCocDepartment(department)) {
        throw new Error("Select your COC department.");
      }

      if (mode === "register") {
        const passwordError = passwordValidationError(password);
        if (passwordError) {
          throw new Error(passwordError);
        }
        if (!lastName.trim() || !firstName.trim()) {
          throw new Error("Enter your last name and first name.");
        }
      }

      const response = await fetch("/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode: awaitingMfa ? "login" : mode,
          email,
          password,
          last_name: mode === "register" ? lastName : undefined,
          first_name: mode === "register" ? firstName : undefined,
          school: COC_SCHOOL_NAME,
          department: mode === "register" ? department : undefined,
          captcha_token: captchaToken ?? undefined,
          mfa_ticket: awaitingMfa ? mfaTicket ?? undefined : undefined,
          mfa_code: awaitingMfa ? mfaCode : undefined,
          mfa_enrollment: awaitingMfa && awaitingMfaEnrollment ? true : undefined,
        }),
      });

      const payload = await readJsonResponse<{
        error?: string;
        ok?: boolean;
        needsEmailConfirmation?: boolean;
        accessPending?: boolean;
        message?: string;
        mfaRequired?: boolean;
        mfaEnrollmentRequired?: boolean;
        mfaTicket?: string;
        captchaRequired?: boolean;
        captchaSiteKey?: string;
      }>(response);

      if (payload.mfaRequired && payload.mfaTicket) {
        setAwaitingMfa(true);
        setAwaitingMfaEnrollment(payload.mfaEnrollmentRequired === true);
        setMfaTicket(payload.mfaTicket);
        setMfaSetupSecret(null);
        setMfaOtpAuthUrl(null);
        setMfaQrDataUrl(null);
        setMfaSetupView("qr");
        setNotice(
          payload.message ??
            (payload.mfaEnrollmentRequired
              ? "Set up two-factor sign-in to continue."
              : "Enter your authenticator code to continue."),
        );
        return;
      }

      if (!response.ok || payload.error) {
        if (payload.captchaRequired) {
          if (payload.captchaSiteKey) {
            setCaptchaSiteKey(payload.captchaSiteKey);
          }
          throw new Error(
            payload.error ??
              "Complete the security check below, then try signing in again.",
          );
        }
        throw new Error(payload.error ?? "Sign in failed.");
      }

      if (mode === "register" && payload.needsEmailConfirmation) {
        setAwaitingApproval(false);
        setAwaitingConfirmation(true);
        setNotice(
          payload.message ??
            "Account created. Keep this page open — after you tap the confirmation link (even on your phone), we will continue here.",
        );
        setMode("login");
        return;
      }

      if (payload.accessPending) {
        setAwaitingConfirmation(false);
        setAwaitingApproval(true);
        setNotice(
          payload.message ??
            "Your email is ready. Ask your COC admin to approve your account before you can open the dashboard.",
        );
        setMode("login");
        return;
      }

      router.push("/dashboard");
      router.refresh();
    } catch (err) {
      const message = err instanceof Error ? err.message : "Sign in failed.";
      const lower = message.toLowerCase();
      if (
        lower.includes("admin approval") ||
        lower.includes("waiting for school admin")
      ) {
        setAwaitingConfirmation(false);
        setAwaitingApproval(true);
        setMode("login");
        setError(null);
        setNotice(null);
      } else if (lower.includes("revoked by your school admin")) {
        setAwaitingConfirmation(false);
        setAwaitingApproval(false);
        setError(message);
      } else if (
        lower.includes("not confirmed") ||
        lower.includes("not verified")
      ) {
        setAwaitingConfirmation(true);
        setError(
          "This email is not confirmed yet. Leave this page open, tap the link in your email (phone or computer), then wait a few seconds.",
        );
      } else if (
        lower.includes("already been taken") ||
        lower.includes("already registered") ||
        lower.includes("already exists")
      ) {
        setAwaitingConfirmation(false);
        setMode("login");
        setError(
          "An account with this email already exists and is approved. Use Login with your password.",
        );
      } else if (
        lower.includes("failed to fetch") ||
        lower.includes("not valid json") ||
        lower.includes("unexpected token") ||
        lower.includes("school server is not responding") ||
        lower.includes("school server is waking up") ||
        lower.includes("aborted") ||
        lower.includes("timeout")
      ) {
        setError(
          awaitingMfa
            ? "The school server is waking up. Wait for a fresh authenticator code, then tap Finish two-factor setup again."
            : "Could not reach the school server. Confirm the API is running, then try again.",
        );
      } else if (awaitingMfa && lower.includes("did not match")) {
        setError(
          "That code did not match. Wait for the next 6-digit code in your authenticator app, then try again.",
        );
      } else if (awaitingMfa && lower.includes("expired")) {
        setError("This step expired. Sign in with your password again to restart two-factor setup.");
        setAwaitingMfa(false);
        setAwaitingMfaEnrollment(false);
        setMfaTicket(null);
        setMfaCode("");
      } else {
        setError(message);
      }
    } finally {
      setLoading(false);
      setSlowServerHint(false);
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
                onClick={() => {
                  setMode(item);
                  if (item === "register") {
                    setAwaitingConfirmation(false);
                  }
                }}
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
                <Label htmlFor="lastName">Last name</Label>
                <Input
                  id="lastName"
                  autoComplete="family-name"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  required
                />
              </div>
              <div className="mb-3">
                <Label htmlFor="firstName">First name</Label>
                <Input
                  id="firstName"
                  autoComplete="given-name"
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  required
                />
                <p className="mt-1 text-xs text-slate-500">
                  We store names as First Last (e.g. Maria Santos) and fix ALL CAPS automatically.
                </p>
              </div>
              <div className="mb-3 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-600">
                <p className="font-semibold text-slate-800">School</p>
                <p>{COC_SCHOOL_NAME}</p>
              </div>
              <div className="mb-3">
                <Label htmlFor="department">Department</Label>
                <select
                  id="department"
                  value={department}
                  onChange={(e) => setDepartment(e.target.value)}
                  required
                  className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm font-semibold text-slate-800 outline-none focus:border-emerald-400"
                >
                  <option value="">Select department</option>
                  {COC_DEPARTMENTS.map((code) => (
                    <option key={code} value={code}>
                      {code}
                    </option>
                  ))}
                </select>
                <p className="mt-1 text-xs text-slate-500">
                  Access is for COC instructors only. After email confirmation, a school admin must
                  approve your account.
                </p>
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
              minLength={mode === "register" ? PASSWORD_MIN_LENGTH : undefined}
              required
            />
            {mode === "register" ? (
              <p className="mt-1 text-xs text-slate-500">{PASSWORD_REQUIREMENT_HINT}</p>
            ) : null}
          </div>

          {awaitingMfa ? (
            <div className="mb-4 space-y-3">
              {awaitingMfaEnrollment ? (
                <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-3 text-sm text-emerald-950">
                  <p className="font-bold">Set up an authenticator app</p>
                  <p className="mt-1">
                    {mfaSetupView === "qr"
                      ? "Scan the QR code with Google Authenticator or Microsoft Authenticator, then enter the 6-digit code below."
                      : "Copy the setup key into your authenticator app (Enter a setup key), then enter the 6-digit code below."}
                  </p>
                  {mfaSetupSecret ? (
                    <div className="mt-3 flex gap-2 rounded-xl bg-emerald-100/80 p-1">
                      {(
                        [
                          ["qr", "Scan QR code"],
                          ["secret", "Setup key"],
                        ] as const
                      ).map(([view, label]) => (
                        <button
                          key={view}
                          type="button"
                          onClick={() => setMfaSetupView(view)}
                          className={`flex-1 rounded-lg py-2 text-xs font-bold ${
                            mfaSetupView === view
                              ? "bg-white text-emerald-800 shadow"
                              : "text-emerald-700"
                          }`}
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                  ) : null}
                  {mfaSetupView === "qr" ? (
                    mfaQrDataUrl ? (
                      <div className="mt-3 flex justify-center">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img
                          src={mfaQrDataUrl}
                          alt="Scan to add COC OMR to your authenticator app"
                          width={220}
                          height={220}
                          className="rounded-lg border border-emerald-200 bg-white p-2"
                        />
                      </div>
                    ) : (
                      <p className="mt-2 text-xs text-emerald-800">
                        {mfaOtpAuthUrl ? "Preparing QR code…" : "Preparing your setup key…"}
                      </p>
                    )
                  ) : mfaSetupSecret ? (
                    <div className="mt-3 rounded-lg border border-emerald-200 bg-white px-3 py-3">
                      <p className="text-xs font-semibold text-emerald-800">Setup key</p>
                      <p className="mt-2 break-all font-mono text-sm font-bold">{mfaSetupSecret}</p>
                      <button
                        type="button"
                        onClick={() => {
                          void navigator.clipboard.writeText(mfaSetupSecret);
                          setNotice("Setup key copied. Paste it in your authenticator app.");
                          setError(null);
                        }}
                        className="mt-2 text-xs font-bold text-emerald-700 hover:underline"
                      >
                        Copy setup key
                      </button>
                    </div>
                  ) : (
                    <p className="mt-2 text-xs text-emerald-800">Preparing your setup key…</p>
                  )}
                  <p className="mt-2 text-xs text-emerald-800">
                    Codes change every 30 seconds. If the server was slow to load, wait for a
                    fresh code before submitting.
                  </p>
                </div>
              ) : null}
              <div>
                <Label htmlFor="mfa">Authenticator code</Label>
                <Input
                  id="mfa"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  value={mfaCode}
                  onChange={(e) => setMfaCode(e.target.value)}
                  required
                />
              </div>
            </div>
          ) : null}

          {captchaSiteKey && !awaitingMfa ? (
            <TurnstileField siteKey={captchaSiteKey} onToken={setCaptchaToken} />
          ) : null}

          {awaitingConfirmation ? (
            <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-3 py-3 text-sm text-amber-950">
              <p className="font-bold">Waiting for email confirmation</p>
              <p className="mt-1">
                We sent a link to{" "}
                <span className="font-semibold">{email.trim() || "your email"}</span>.
                Leave this page open. After you tap the link on your phone or computer, this
                page will continue automatically.
              </p>
            </div>
          ) : null}

          {awaitingApproval ? (
            <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-3 py-3 text-sm text-amber-950">
              <p className="font-bold">Waiting for school admin approval</p>
              <p className="mt-1">
                Your email is confirmed. Ask your COC admin to approve you under{" "}
                <strong>Admin → Access control</strong>, then sign in again.
              </p>
            </div>
          ) : null}

          {slowServerHint ? (
            <p className="mb-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-sm font-semibold text-amber-900">
              Connecting to the school server — free cloud hosting can take up to a minute the first
              time. Stay on this page.
            </p>
          ) : null}

          {notice ? (
            <p className="mb-3 rounded-xl bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800">
              {notice}
            </p>
          ) : null}

          {error ? (
            <p className="mb-3 rounded-xl bg-red-50 px-3 py-2 text-sm font-semibold text-red-700">{error}</p>
          ) : null}

          <Button
            type="submit"
            className="w-full"
            disabled={loading || resendLoading || (awaitingMfaEnrollment && !mfaSetupSecret)}
          >
            {loading
              ? awaitingMfa
                ? "Verifying code — server may take up to a minute…"
                : slowServerHint
                  ? "Connecting to server…"
                  : "Please wait…"
              : mode === "register"
                ? "Create account"
                : awaitingMfa
                  ? awaitingMfaEnrollment
                    ? "Finish two-factor setup"
                    : "Verify code"
                  : "Sign in"}
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
          ) : null}
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
