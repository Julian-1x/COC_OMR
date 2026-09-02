import { describe, expect, it, vi } from "vitest";
import { withAutoRetry } from "@/lib/api/wake-api";

describe("withAutoRetry", () => {
  it("returns on first success", async () => {
    const fn = vi.fn().mockResolvedValue("ok");
    await expect(withAutoRetry(fn)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("retries until success", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new Error("slow"))
      .mockRejectedValueOnce(new Error("still slow"))
      .mockResolvedValue("ready");

    await expect(
      withAutoRetry(fn, { maxAttempts: 4, delayMs: 1, onRetry: vi.fn() }),
    ).resolves.toBe("ready");
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("throws after max attempts", async () => {
    const fn = vi.fn().mockRejectedValue(new Error("down"));
    await expect(withAutoRetry(fn, { maxAttempts: 3, delayMs: 1 })).rejects.toThrow("down");
    expect(fn).toHaveBeenCalledTimes(3);
  });
});
