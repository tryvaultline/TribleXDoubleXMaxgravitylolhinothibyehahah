import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

export function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function fingerprint(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex").slice(0, 32).toUpperCase();
}

export function safeEqualHash(rawValue: string, expectedHash: string): boolean {
  const actual = Buffer.from(sha256(rawValue), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  if (actual.length !== expected.length) {
    return false;
  }
  return timingSafeEqual(actual, expected);
}
