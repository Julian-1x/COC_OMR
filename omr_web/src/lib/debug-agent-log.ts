/** Debug-mode ingest helper. Do not log secrets/tokens/PII. */

function payload(
  location: string,
  message: string,
  data: Record<string, unknown>,
  hypothesisId: string,
) {
  return {
    sessionId: "cc7a38",
    location,
    message,
    data,
    hypothesisId,
    timestamp: Date.now(),
  };
}

export function agentDebugLog(
  location: string,
  message: string,
  data: Record<string, unknown>,
  hypothesisId: string,
): void {
  // #region agent log
  const body = payload(location, message, data, hypothesisId);

  // Browser / Edge: HTTP ingest (works on http://localhost)
  try {
    fetch("http://127.0.0.1:7835/ingest/66559ec0-f9a7-4749-a867-c6e887cfcfff", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Debug-Session-Id": "cc7a38",
      },
      body: JSON.stringify(body),
    }).catch(() => {});
  } catch {
    // ignore
  }

  // Node server routes: also append NDJSON to workspace log file
  if (typeof window === "undefined") {
    try {
      // Dynamic require keeps this out of the client bundle.
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const fs = require("fs") as typeof import("fs");
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const path = require("path") as typeof import("path");
      const logPath = path.join(process.cwd(), "..", "debug-cc7a38.log");
      const altPath = path.join(process.cwd(), "debug-cc7a38.log");
      const target = fs.existsSync(path.join(process.cwd(), "..", "omr_web"))
        ? logPath
        : altPath;
      // When cwd is omr_web, write to repo root; also try omr_web/debug as fallback.
      const candidates = [
        path.join(process.cwd(), "..", "debug-cc7a38.log"),
        path.join(process.cwd(), "debug-cc7a38.log"),
        "d:/omr_app/debug-cc7a38.log",
      ];
      for (const file of candidates) {
        try {
          fs.appendFileSync(file, `${JSON.stringify(body)}\n`, "utf8");
          break;
        } catch {
          // try next
        }
      }
    } catch {
      // ignore
    }
  }
  // #endregion
}
