import { execSync } from "node:child_process";
import { X509Certificate } from "node:crypto";
import crypto from "node:crypto";
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export interface CertPair {
  cert: Buffer;
  key: Buffer;
  fingerprint: string;
  sanIps: string[];
  subject: string;
  validFrom: string;
  validTo: string;
}

interface CertificateDetails {
  fingerprint: string;
  sanIps: string[];
  subject: string;
  validFrom: string;
  validTo: string;
}

export function getOrCreateCert(localDir: string, requestedLanIps: string[] = []): CertPair {
  const certPath = join(localDir, "cert.pem");
  const keyPath = join(localDir, "key.pem");
  const configPath = join(localDir, "cert-openssl.cnf");
  const requiredSanIps = normalizeSanIps(requestedLanIps);

  let shouldRotate = !existsSync(certPath) || !existsSync(keyPath);
  if (!shouldRotate) {
    try {
      shouldRotate = certificateNeedsRotation(readCertificateDetails(readFileSync(certPath)), requiredSanIps);
    } catch {
      shouldRotate = true;
    }
  }

  if (shouldRotate) {
    generateCertificate({ certPath, keyPath, configPath, sanIps: requiredSanIps });
  }

  const cert = readFileSync(certPath);
  const key = readFileSync(keyPath);
  const details = readCertificateDetails(cert);

  return {
    cert,
    key,
    fingerprint: details.fingerprint,
    sanIps: details.sanIps,
    subject: details.subject,
    validFrom: details.validFrom,
    validTo: details.validTo
  };
}

function generateCertificate(options: { certPath: string; keyPath: string; configPath: string; sanIps: string[] }) {
  console.log("Generating self-signed certificate...");
  const { certPath, keyPath, configPath, sanIps } = options;
  const gitOpenssl = "C:\\Program Files\\Git\\usr\\bin\\openssl.exe";
  let opensslCmd = "openssl";

  if (existsSync(gitOpenssl)) {
    opensslCmd = `"${gitOpenssl}"`;
  }

  rmSync(certPath, { force: true });
  rmSync(keyPath, { force: true });

  writeFileSync(
    configPath,
    [
      "[req]",
      "distinguished_name = dn",
      "x509_extensions = v3_req",
      "prompt = no",
      "",
      "[dn]",
      "CN = maxgravity-local-bridge",
      "O = Maxgravity Local Bridge",
      "",
      "[v3_req]",
      "basicConstraints = critical, CA:false",
      "keyUsage = critical, digitalSignature, keyAgreement",
      "extendedKeyUsage = serverAuth",
      "subjectAltName = @alt_names",
      "",
      "[alt_names]",
      ...sanIps.map((ip, index) => `IP.${index + 1} = ${ip}`)
    ].join("\n"),
    "utf8"
  );

  const command = `${opensslCmd} req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -pkeyopt ec_param_enc:named_curve -keyout "${keyPath}" -out "${certPath}" -sha256 -days 825 -nodes -config "${configPath}"`;

  try {
    execSync(command, { stdio: "pipe" });
  } catch (err: any) {
    console.warn("Failed to generate certificate using OpenSSL: " + err.message);
    try {
      execSync(
        `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -pkeyopt ec_param_enc:named_curve -keyout "${keyPath}" -out "${certPath}" -sha256 -days 825 -nodes -config "${configPath}"`,
        { stdio: "pipe" }
      );
    } catch (err2: any) {
      throw new Error(`Failed to generate certificate with OpenSSL: ${err2.message}`);
    }
  }
}

function normalizeSanIps(requestedLanIps: string[]): string[] {
  const values = new Set(["127.0.0.1", ...requestedLanIps.filter(Boolean)]);
  return Array.from(values);
}

function certificateNeedsRotation(details: CertificateDetails, requiredSanIps: string[]): boolean {
  if (requiredSanIps.some((ip) => !details.sanIps.includes(ip))) {
    return true;
  }

  const validTo = new Date(details.validTo);
  const validFrom = new Date(details.validFrom);
  const now = Date.now();

  if (Number.isNaN(validTo.getTime()) || Number.isNaN(validFrom.getTime())) {
    return true;
  }

  if (validFrom.getTime() > now) {
    return true;
  }

  const daysRemaining = (validTo.getTime() - now) / (24 * 60 * 60 * 1000);
  return daysRemaining < 14;
}

function readCertificateDetails(cert: Buffer): CertificateDetails {
  const parsed = new X509Certificate(cert);
  const sanIps = (parsed.subjectAltName ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.startsWith("IP Address:"))
    .map((entry) => entry.replace("IP Address:", "").trim());

  return {
    fingerprint: derFingerprint(cert),
    sanIps,
    subject: parsed.subject,
    validFrom: parsed.validFrom,
    validTo: parsed.validTo
  };
}

function derFingerprint(cert: Buffer): string {
  const certText = cert.toString("utf8");
  const base64 = certText
    .replace(/-----BEGIN CERTIFICATE-----/, "")
    .replace(/-----END CERTIFICATE-----/, "")
    .replace(/\s+/g, "");
  const der = Buffer.from(base64, "base64");
  return crypto.createHash("sha256").update(der).digest("hex").toUpperCase();
}
