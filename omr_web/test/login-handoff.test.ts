import { describe, expect, it } from "vitest";
import { sealLoginHandoff, unsealLoginHandoff } from "@/lib/api/login-handoff";

describe("login handoff seal", () => {
  it("round-trips a Sanctum token", () => {
    process.env.AUTH_SECRET = "test-secret-for-handoff";
    const token = "42|abcdefghijklmnopqrstuvwxyz0123456789";
    const sealed = sealLoginHandoff(token);
    expect(sealed).not.toContain("|");
    expect(unsealLoginHandoff(sealed)).toBe(token);
  });

  it("rejects tampered payloads", () => {
    process.env.AUTH_SECRET = "test-secret-for-handoff";
    const sealed = sealLoginHandoff("9|abc");
    expect(unsealLoginHandoff(`${sealed}x`)).toBeNull();
  });
});
