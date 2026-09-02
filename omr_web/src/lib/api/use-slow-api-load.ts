"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getPublicApiBaseUrl } from "@/lib/api/env";
import { wakeSchoolApi, withAutoRetry } from "@/lib/api/wake-api";

const DEFAULT_MAX_ATTEMPTS = 10;
const DEFAULT_RETRY_DELAY_MS = 4000;

export type SlowApiLoadOptions = {
  maxAttempts?: number;
  retryDelayMs?: number;
};

export type SlowApiLoadState = {
  loading: boolean;
  error: string | null;
  attempt: number;
  maxAttempts: number;
  retrying: boolean;
  reload: () => void;
};

/**
 * Load dashboard data with API wake-up + automatic retries while the host is slow.
 */
export function useSlowApiLoad(
  runner: () => Promise<void>,
  deps: unknown[],
  options?: SlowApiLoadOptions,
): SlowApiLoadState {
  const maxAttempts = options?.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const retryDelayMs = options?.retryDelayMs ?? DEFAULT_RETRY_DELAY_MS;
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);
  const [loadKey, setLoadKey] = useState(0);
  const reload = useCallback(() => setLoadKey((key) => key + 1), []);
  const runnerRef = useRef(runner);
  runnerRef.current = runner;

  useEffect(() => {
    let cancelled = false;

    async function run() {
      setLoading(true);
      setError(null);
      setAttempt(0);

      try {
        await withAutoRetry(
          async () => {
            if (cancelled) return;
            await wakeSchoolApi(getPublicApiBaseUrl(), {
              attempts: 3,
              delayMs: 2000,
              probeTimeoutMs: 30_000,
            });
            if (cancelled) return;
            await runnerRef.current();
          },
          {
            maxAttempts,
            delayMs: retryDelayMs,
            onRetry: (retryAttempt) => {
              if (!cancelled) setAttempt(retryAttempt);
            },
          },
        );
      } catch (err) {
        if (cancelled) return;
        setError(
          err instanceof Error
            ? err.message
            : "Could not load data. The school server may still be waking up.",
        );
      } finally {
        if (!cancelled) {
          setLoading(false);
          setAttempt(0);
        }
      }
    }

    void run();
    return () => {
      cancelled = true;
    };
  }, [...deps, loadKey, maxAttempts, retryDelayMs]);

  return {
    loading,
    error,
    attempt,
    maxAttempts,
    retrying: loading && attempt > 0,
    reload,
  };
}

export function slowApiLoadingMessage(attempt: number, maxAttempts: number): string {
  if (attempt <= 0) {
    return "The school server may take up to a minute to wake up on first visit.";
  }
  return `Server waking up — retrying automatically (${attempt}/${maxAttempts})…`;
}
