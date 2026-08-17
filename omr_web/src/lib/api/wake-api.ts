function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/** Ping Laravel /up so free-tier hosts (Render) finish waking before auth. */
export async function wakeSchoolApi(
  apiBase: string,
  options?: { attempts?: number; delayMs?: number; probeTimeoutMs?: number },
): Promise<boolean> {
  const base = apiBase.replace(/\/$/, "");
  const attempts = options?.attempts ?? 3;
  const delayMs = options?.delayMs ?? 2000;
  const probeTimeoutMs = options?.probeTimeoutMs ?? 25_000;

  for (let i = 0; i < attempts; i += 1) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), probeTimeoutMs);
      const response = await fetch(`${base}/up`, {
        cache: "no-store",
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (response.ok) {
        return true;
      }
    } catch {
      // First probe often wakes a sleeping host; keep trying.
    }
    if (i + 1 < attempts) {
      await delay(delayMs);
    }
  }
  return false;
}

function isRetryableStatus(status: number): boolean {
  return status === 502 || status === 503 || status === 504;
}

/** Auth calls need extra patience while Render cold-starts. */
export async function fetchAuthUpstream(
  url: string,
  init: RequestInit,
  options?: { attempts?: number; timeoutMs?: number },
): Promise<Response> {
  const attempts = options?.attempts ?? 3;
  const timeoutMs = options?.timeoutMs ?? 45_000;
  let lastError: unknown;

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, { ...init, signal: controller.signal });
      clearTimeout(timer);
      if (response.ok || !isRetryableStatus(response.status)) {
        return response;
      }
      lastError = new Error(`Upstream ${response.status}`);
    } catch (error) {
      clearTimeout(timer);
      lastError = error;
    }

    if (attempt + 1 < attempts) {
      await delay(2500);
    }
  }

  if (lastError instanceof Error) {
    throw lastError;
  }
  throw new Error("Could not reach the school API.");
}
