import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import crypto from "node:crypto";

export interface CertPair {
  cert: Buffer;
  key: Buffer;
  fingerprint: string;
}

export function getOrCreateCert(localDir: string): CertPair {
  const certPath = join(localDir, "cert.pem");
  const keyPath = join(localDir, "key.pem");

  if (!existsSync(certPath) || !existsSync(keyPath)) {
    console.log("Generating self-signed certificate...");
    const gitOpenssl = "C:\\Program Files\\Git\\usr\\bin\\openssl.exe";
    let opensslCmd = "openssl";

    if (existsSync(gitOpenssl)) {
      opensslCmd = `"${gitOpenssl}"`;
    }

    try {
      execSync(
        `${opensslCmd} req -x509 -newkey rsa:2048 -keyout "${keyPath}" -out "${certPath}" -sha256 -days 3650 -nodes -subj "/CN=maxgravity-local-bridge"`,
        { stdio: "pipe" }
      );
    } catch (err: any) {
      console.warn("Failed to generate certificate using OpenSSL: " + err.message);
      // Fallback in case standard openssl works
      try {
        execSync(
          `openssl req -x509 -newkey rsa:2048 -keyout "${keyPath}" -out "${certPath}" -sha256 -days 3650 -nodes -subj "/CN=maxgravity-local-bridge"`,
          { stdio: "pipe" }
        );
      } catch (err2: any) {
        throw new Error(`Failed to generate certificate with OpenSSL: ${err2.message}`);
      }
    }
  }

  const cert = readFileSync(certPath);
  const key = readFileSync(keyPath);

  // Extract DER from PEM to get SHA-256 fingerprint (matching iOS SecCertificateCopyData fingerprint)
  const certText = cert.toString("utf8");
  const base64 = certText
    .replace(/-----BEGIN CERTIFICATE-----/, "")
    .replace(/-----END CERTIFICATE-----/, "")
    .replace(/\s+/g, "");
  const der = Buffer.from(base64, "base64");
  const fingerprint = crypto.createHash("sha256").update(der).digest("hex").toUpperCase();

  return { cert, key, fingerprint };
}
