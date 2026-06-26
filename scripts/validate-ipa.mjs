import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";

const [ipaPath, expectedBundleId, expectedDisplayName, shaPath] = process.argv.slice(2);

if (!ipaPath || !expectedBundleId || !expectedDisplayName || !shaPath) {
  console.error("Usage: node scripts/validate-ipa.mjs <ipaPath> <bundleId> <displayName> <shaOutPath>");
  process.exit(1);
}

if (!existsSync(ipaPath)) {
  console.error(`IPA not found: ${ipaPath}`);
  process.exit(1);
}

const tmpDir = mkdtempSync(path.join(os.tmpdir(), "maxgravity-ipa-"));

try {
  execFileSync("unzip", ["-q", ipaPath, "-d", tmpDir], { stdio: "pipe" });
  const appPath = path.join(tmpDir, "Payload", "Maxgravity.app");
  const infoPlist = path.join(appPath, "Info.plist");

  if (!existsSync(appPath) || !existsSync(infoPlist)) {
    throw new Error("IPA is missing Payload/Maxgravity.app or Info.plist.");
  }

  const plistJson = execFileSync("plutil", ["-convert", "json", "-o", "-", infoPlist], { encoding: "utf8" });
  const plist = JSON.parse(plistJson);

  const bundleId = plist.CFBundleIdentifier;
  const displayName = plist.CFBundleDisplayName ?? plist.CFBundleName;
  const executableName = plist.CFBundleExecutable;
  const executablePath = path.join(appPath, executableName);

  if (bundleId !== expectedBundleId) {
    throw new Error(`Bundle identifier mismatch: ${bundleId} !== ${expectedBundleId}`);
  }

  if (displayName !== expectedDisplayName) {
    throw new Error(`Display name mismatch: ${displayName} !== ${expectedDisplayName}`);
  }

  const lipoInfo = execFileSync("lipo", ["-info", executablePath], { encoding: "utf8" });
  if (!/arm64/.test(lipoInfo)) {
    throw new Error(`Device binary is missing arm64: ${lipoInfo.trim()}`);
  }
  if (/x86_64/.test(lipoInfo) || /arm64e x86_64/.test(lipoInfo)) {
    throw new Error(`Simulator architecture detected in IPA binary: ${lipoInfo.trim()}`);
  }

  const binaryStrings = execFileSync("strings", [executablePath], { encoding: "utf8", maxBuffer: 20 * 1024 * 1024 });
  const forbiddenBinaryTerms = ["_UILiquidLensView", "CABackdropLayer", "BEGIN PRIVATE KEY", "mock-session-12345678", "release-fixture"];
  const hit = forbiddenBinaryTerms.find((term) => binaryStrings.includes(term));
  if (hit) {
    throw new Error(`Forbidden string detected in IPA binary: ${hit}`);
  }

  const hash = crypto.createHash("sha256").update(readFileSync(ipaPath)).digest("hex");
  execFileSync("bash", ["-lc", `printf '%s  %s\n' '${hash}' '${path.basename(ipaPath)}' > '${shaPath}'`], { stdio: "pipe" });

  console.log(JSON.stringify({
    bundleId,
    displayName,
    lipoInfo: lipoInfo.trim(),
    sha256: hash
  }));
} finally {
  rmSync(tmpDir, { recursive: true, force: true });
}
