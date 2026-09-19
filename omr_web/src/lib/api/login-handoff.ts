import { createCipheriv, createDecipheriv, createHash, randomBytes } from "crypto";

const HANDOFF_TTL_MS = 2 * 60 * 1000;

function handoffSecret(): string {
  const secret =
    process.env.AUTH_SECRET?.trim() ||
    process.env.API_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_API_BASE_URL?.trim();
  if (!secret) {
    throw new Error("AUTH_SECRET or API_BASE_URL is required to seal login handoffs.");
  }
  return secret;
}

function keyBytes(): Buffer {
  return createHash("sha256").update(handoffSecret()).digest();
}

/**
 * Short-lived sealed Sanctum token for a one-shot form POST to /auth/after-login.
 * Avoids relying on Set-Cookie from a fetch() JSON response (unreliable on some hosts).
 */
export function sealLoginHandoff(token: string): string {
  const key = keyBytes();
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const expiresAt = String(Date.now() + HANDOFF_TTL_MS);
  const plaintext = `${expiresAt}.${token}`;
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString("base64url");
}

export function unsealLoginHandoff(sealed: string): string | null {
  try {
    const raw = Buffer.from(sealed.trim(), "base64url");
    if (raw.length < 12 + 16 + 1) return null;
    const iv = raw.subarray(0, 12);
    const tag = raw.subarray(12, 28);
    const encrypted = raw.subarray(28);
    const decipher = createDecipheriv("aes-256-gcm", keyBytes(), iv);
    decipher.setAuthTag(tag);
    const plaintext = Buffer.concat([
      decipher.update(encrypted),
      decipher.final(),
    ]).toString("utf8");
    const dot = plaintext.indexOf(".");
    if (dot <= 0) return null;
    const expiresAt = Number(plaintext.slice(0, dot));
    const token = plaintext.slice(dot + 1);
    if (!Number.isFinite(expiresAt) || Date.now() > expiresAt) return null;
    if (!token.includes("|")) return null;
    return token;
  } catch {
    return null;
  }
}
