import { spawnSync } from "node:child_process";

function runProtectedData(command: string, secret: string): string {
  if (process.platform !== "win32") {
    throw new Error("DPAPI is only available on Windows");
  }

  const result = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", command],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        MG_DPAPI_SECRET: secret
      }
    }
  );

  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || "DPAPI command failed");
  }

  return result.stdout.trim();
}

export function protectForCurrentUser(plainText: string): string {
  return runProtectedData(
    "Add-Type -AssemblyName System.Security;" +
      "$bytes=[System.Text.Encoding]::UTF8.GetBytes($env:MG_DPAPI_SECRET);" +
      "$protected=[System.Security.Cryptography.ProtectedData]::Protect($bytes,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);" +
      "[Convert]::ToBase64String($protected)",
    plainText
  );
}

export function unprotectForCurrentUser(protectedBase64: string): string {
  return runProtectedData(
    "Add-Type -AssemblyName System.Security;" +
      "$bytes=[Convert]::FromBase64String($env:MG_DPAPI_SECRET);" +
      "$plain=[System.Security.Cryptography.ProtectedData]::Unprotect($bytes,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);" +
      "[System.Text.Encoding]::UTF8.GetString($plain)",
    protectedBase64
  );
}
