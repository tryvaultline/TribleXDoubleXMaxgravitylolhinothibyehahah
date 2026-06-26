import { exec, spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";
import { AntigravityCliAccountAdapter } from "./antigravity-adapter.js";
import { FileTrustStore } from "./trust-store.js";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, "..", "..");
const localDir = join(projectRoot, "bridge", ".local");
const pidFile = join(localDir, "bridge.pid");
const port = Number(process.env.MAXGRAVITY_BRIDGE_PORT ?? "59443");
const trustStorePath = process.env.MAXGRAVITY_TRUST_STORE ?? join(localDir, "trusted-devices.json");
const trustStore = new FileTrustStore(trustStorePath);

function getStartupFilePath(): string | null {
  if (process.platform !== "win32") return null;
  const appData = process.env.APPDATA;
  if (!appData) return null;
  return join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "maxgravity-bridge.bat");
}

async function isBridgeRunning(): Promise<boolean> {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/v1/connection/health`);
    if (response.ok) {
      const data = await response.json() as any;
      return data.product === "Maxgravity Bridge";
    }
  } catch {
    // Failed to connect means offline
  }
  return false;
}

async function startBridge(): Promise<void> {
  const running = await isBridgeRunning();
  if (running) {
    console.log("Maxgravity Bridge is already running.");
    return;
  }

  console.log("Starting Maxgravity Bridge...");
  const nodePath = process.execPath;
  const serverIndex = join(projectRoot, "bridge", "dist", "src", "index.js");
  
  const child = spawn(nodePath, [serverIndex], {
    cwd: join(projectRoot, "bridge"),
    detached: true,
    stdio: "ignore",
    shell: false
  });
  console.log(`Spawned PID: ${child.pid}`);
  child.on("error", (err) => {
    console.error("Failed to start bridge process:", err);
  });
  child.unref();

  // Wait 2 seconds for server to start
  await new Promise(resolve => setTimeout(resolve, 2000));
}

async function getPairingSession() {
  const url = `http://127.0.0.1:${port}/v1/connection/pairing-sessions`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json"
    },
    body: "{}"
  });
  if (!response.ok) {
    throw new Error(`Failed to create pairing session: ${response.statusText}`);
  }
  return await response.json() as any;
}

async function pair() {
  await startBridge();
  
  try {
    const session = await getPairingSession();
    const localIp = new URL(session.address.replace(/^wss:/, "https:")).hostname;
    const computerName = os.hostname();
    
    console.log("\n=== Pairing Session Details ===");
    console.log(`Computer Name: ${computerName}`);
    console.log(`Local IP:      ${localIp}`);
    console.log(`Session ID:    ${session.sessionId}`);
    console.log(`Token:         ${session.token}`);
    console.log(`Fingerprint:   ${session.bridgeFingerprint}`);
    console.log(`Expires At:    ${session.expiresAt}`);
    console.log("===============================\n");
    
    // Generate static HTML pairing page with pending approval loop
    const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <title>Maxgravity Pairing Setup</title>
  <style>
    body {
      background-color: #0d0d0e;
      color: #f6f5f2;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
    }
    .card {
      background-color: #161618;
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 28px;
      padding: 40px;
      width: 440px;
      text-align: center;
      box-shadow: 0 20px 40px rgba(0,0,0,0.6);
      backdrop-filter: blur(12px);
    }
    h1 {
      font-size: 28px;
      font-weight: 700;
      margin: 10px 0 20px 0;
      background: linear-gradient(135deg, #ffffff 0%, #a1a1a5 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .computer {
      font-size: 13px;
      font-weight: 600;
      color: rgba(255,255,255,0.7);
      background-color: rgba(255,255,255,0.07);
      padding: 6px 14px;
      border-radius: 20px;
      display: inline-block;
      margin-bottom: 20px;
      border: 1px solid rgba(255,255,255,0.05);
    }
    .qr-container {
      background-color: #fff;
      padding: 20px;
      border-radius: 24px;
      display: inline-block;
      margin: 20px 0;
      box-shadow: 0 10px 25px rgba(0,0,0,0.3);
    }
    .countdown {
      font-size: 15px;
      color: #ffd000;
      font-weight: 600;
      margin-bottom: 10px;
    }
    .status {
      margin-top: 10px;
      font-size: 14px;
      color: rgba(255,255,255,0.5);
    }
    .pending-section {
      display: none;
      text-align: left;
      margin-top: 20px;
    }
    .device-card {
      background-color: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: 18px;
      padding: 20px;
      margin-bottom: 15px;
    }
    .btn {
      padding: 10px 20px;
      border-radius: 12px;
      font-weight: 600;
      cursor: pointer;
      border: none;
      font-size: 14px;
      transition: all 0.2s ease;
    }
    .btn-approve {
      background: linear-gradient(135deg, #30d158 0%, #248a3d 100%);
      color: #fff;
      margin-right: 10px;
    }
    .btn-approve:hover {
      opacity: 0.9;
      transform: translateY(-1px);
    }
    .btn-reject {
      background-color: rgba(255, 255, 255, 0.08);
      color: #ff453a;
      border: 1px solid rgba(255, 69, 58, 0.2);
    }
    .btn-reject:hover {
      background-color: rgba(255, 69, 58, 0.1);
    }
    .actions {
      display: flex;
      margin-top: 15px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="computer">${computerName} (${localIp})</div>
    
    <div id="qr-section">
      <h1>Connect Maxgravity</h1>
      <p style="font-size: 14px; color: rgba(255,255,255,0.6); line-height: 1.5;">Scan this QR code from the Maxgravity app on your iPhone.</p>
      
      <div class="qr-container" id="qrcode"></div>
      
      <div class="countdown" id="countdown">Token expires in 5:00</div>
      <div style="font-size:12px; color: rgba(255,255,255,0.4); margin-bottom: 10px;">Fingerprint: ${session.bridgeFingerprint}</div>
      <div class="status" id="status">Waiting for iPhone scan...</div>
    </div>

    <div id="pending-section" class="pending-section">
      <h2 style="font-size: 20px; margin-top: 0; margin-bottom: 10px;">Approval Required</h2>
      <p style="font-size: 13px; color: rgba(255,255,255,0.6); margin-bottom: 20px;">Confirm that the fingerprint on your iPhone matches the suffix below.</p>
      <div id="pending-container"></div>
    </div>
  </div>

  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
  <script>
    const payload = ${JSON.stringify(session)};
    const qrData = JSON.stringify(payload);
    new QRCode(document.getElementById("qrcode"), {
      text: qrData,
      width: 256,
      height: 256,
      colorDark: "#000000",
      colorLight: "#ffffff",
      correctLevel: QRCode.CorrectLevel.H
    });

    let expires = new Date(payload.expiresAt).getTime();
    const interval = setInterval(() => {
      const now = new Date().getTime();
      const diff = expires - now;
      if (diff <= 0) {
        clearInterval(interval);
        document.getElementById("countdown").innerText = "Token Expired";
        document.getElementById("countdown").style.color = "#ff453a";
        document.getElementById("status").innerText = "Please regenerate the pairing QR code.";
      } else {
        const mins = Math.floor(diff / 60000);
        const secs = Math.floor((diff % 60000) / 1000);
        document.getElementById("countdown").innerText = \`Token expires in \${mins}:\${secs < 10 ? '0' : ''}\${secs}\`;
      }
    }, 1000);

    async function approveDevice(id) {
      try {
        const res = await fetch(\`http://127.0.0.1:${port}/v1/connection/pending-devices/\${id}/approve\`, { method: "POST" });
        if (res.ok) {
          alert("Device approved successfully!");
          location.reload();
        } else {
          alert("Failed to approve device.");
        }
      } catch (err) {
        alert("Connection error: " + err.message);
      }
    }

    async function rejectDevice(id) {
      try {
        const res = await fetch(\`http://127.0.0.1:${port}/v1/connection/pending-devices/\${id}/reject\`, { method: "POST" });
        if (res.ok) {
          alert("Device pairing request rejected.");
          location.reload();
        } else {
          alert("Failed to reject device.");
        }
      } catch (err) {
        alert("Connection error: " + err.message);
      }
    }

    // Poll pending devices
    setInterval(async () => {
      try {
        const res = await fetch("http://127.0.0.1:${port}/v1/connection/pending-devices");
        if (res.ok) {
          const devices = await res.json();
          const qrSec = document.getElementById("qr-section");
          const pendSec = document.getElementById("pending-section");
          const container = document.getElementById("pending-container");
          
          if (devices && devices.length > 0) {
            qrSec.style.display = "none";
            pendSec.style.display = "block";
            
            let html = "";
            for (const dev of devices) {
              const remaining = Math.max(0, Math.floor((new Date(dev.expiresAt).getTime() - Date.now()) / 1000));
              const mins = Math.floor(remaining / 60);
              const secs = remaining % 60;
              const timeStr = remaining > 0 ? \`\${mins}:\${secs < 10 ? '0' : ''}\${secs}\` : "Expired";
              
              html += \`
                <div class="device-card">
                  <div style="font-weight: 600; font-size: 16px; margin-bottom: 6px;">\${dev.deviceName}</div>
                  <div style="font-size: 13px; color: rgba(255,255,255,0.6); margin-bottom: 4px;">Platform: \${dev.devicePlatform}</div>
                  <div style="font-size: 13px; color: rgba(255,255,255,0.6); margin-bottom: 4px;">IP Address: \${dev.clientIp}</div>
                  <div style="font-size: 13px; color: rgba(255,255,255,0.6); margin-bottom: 8px;">Fingerprint Suffix: ...\${dev.publicKeyFingerprint.slice(-8)}</div>
                  <div style="font-size: 13px; color: #ffd000; margin-bottom: 12px;">Expires in: \${timeStr}</div>
                  <div class="actions">
                    <button class="btn btn-approve" onclick="approveDevice('\${dev.id}')">Approve</button>
                    <button class="btn btn-reject" onclick="rejectDevice('\${dev.id}')">Reject</button>
                  </div>
                </div>
              \`;
            }
            container.innerHTML = html;
          } else {
            qrSec.style.display = "block";
            pendSec.style.display = "none";
          }
        }
      } catch (err) {}
    }, 2000);
  </script>
</body>
</html>
    `;

    const htmlPath = join(localDir, "pair.html");
    writeFileSync(htmlPath, htmlContent);
    console.log(`Generated pairing page at: ${htmlPath}`);

    if (process.platform === "win32") {
      exec(`explorer.exe "${htmlPath}"`);
    } else {
      exec(`open "${htmlPath}"`);
    }
    console.log("Waiting for iPhone scan. Check your default browser.");

  } catch (err: any) {
    console.error("Pairing command failed:", err.message);
  }
}

async function doctor() {
  console.log("=== Maxgravity Bridge Doctor ===");
  
  const adapter = new AntigravityCliAccountAdapter();
  const agentApiBat = "C:\\Users\\kuroi\\.gemini\\antigravity\\bin\\agentapi.bat";
  const cliInstalled = existsSync(agentApiBat);
  console.log(`Antigravity CLI: ${cliInstalled ? "Installed" : "Missing"}`);
  
  let authenticated = false;
  if (cliInstalled) {
    const session = adapter.discoverSession();
    if (session.token && session.address) {
      try {
        const { execSync } = await import("node:child_process");
        execSync(`"${agentApiBat}" get-conversation-metadata dummy-id`, {
          env: {
            ...process.env,
            ANTIGRAVITY_LS_ADDRESS: session.address,
            ANTIGRAVITY_CSRF_TOKEN: session.token
          },
          stdio: ["ignore", "pipe", "pipe"]
        });
        authenticated = true;
      } catch (err: any) {
        const errOutput = err.stdout?.toString() || err.stderr?.toString() || err.message || "";
        if (errOutput.includes("trajectory not found")) {
          authenticated = true;
        }
      }
    }
  }
  console.log(`Local Account Authentication: ${authenticated ? "Authenticated" : "Not Authenticated"}`);
  
  const running = await isBridgeRunning();
  console.log(`Bridge Status: ${running ? "Online" : "Offline"}`);
  
  const pkgPath = join(projectRoot, "bridge", "package.json");
  let version = "0.1.0";
  if (existsSync(pkgPath)) {
    const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
    version = pkg.version || "0.1.0";
  }
  console.log(`Bridge Version: ${version}`);
  
  const workspaceAccessible = existsSync(projectRoot);
  console.log(`Workspace Access Status: ${workspaceAccessible ? "Accessible (Approved)" : "Inaccessible"}`);
  
  // Windows startup diagnostics
  const startupPath = getStartupFilePath();
  const startupInstalled = startupPath ? existsSync(startupPath) : false;
  console.log(`Automatic Startup Status: ${startupInstalled ? "Installed" : "Not Installed"}`);
  
  let deviceCount = 0;
  try {
    const devs = await trustStore.list();
    deviceCount = devs.filter(d => !d.revokedAt).length;
  } catch {
    // Ignore error
  }
  console.log(`Trusted-device count: ${deviceCount}`);
  
  console.log(`QR Readiness: ${running ? "Ready" : "Not Ready (Start the bridge first)"}`);
  console.log("API Key: No API key required");
  console.log("================================");
  
  adapter.stop();
}

async function status() {
  const running = await isBridgeRunning();
  if (running) {
    const pid = readFileSync(pidFile, "utf8");
    console.log(`Maxgravity Bridge is running (PID: ${pid}) on port ${port}.`);
  } else {
    console.log("Maxgravity Bridge is offline.");
  }
}

async function stop() {
  const running = await isBridgeRunning();
  if (!running) {
    console.log("Maxgravity Bridge is not running.");
    return;
  }

  const pid = Number(readFileSync(pidFile, "utf8"));
  console.log(`Stopping Maxgravity Bridge (PID: ${pid})...`);
  try {
    process.kill(pid, "SIGTERM");
    unlinkSync(pidFile);
    console.log("Bridge stopped successfully.");
  } catch (err: any) {
    console.error("Failed to stop bridge:", err.message);
  }
}

async function devices() {
  try {
    const devs = await trustStore.list();
    if (devs.length === 0) {
      console.log("No trusted devices found.");
      return;
    }
    console.log("Trusted Devices:");
    devs.forEach((d: any) => {
      console.log(`- ID: ${d.id}`);
      console.log(`  Name: ${d.name}`);
      console.log(`  Fingerprint: ${d.publicKeyFingerprint}`);
      console.log(`  Paired At: ${d.pairedAt}`);
      if (d.revokedAt) {
        console.log(`  Status: Revoked (at ${d.revokedAt})`);
      } else {
        console.log(`  Status: Active`);
      }
    });
  } catch (err: any) {
    console.error("Failed to read trusted devices:", err.message);
  }
}

async function revokeDevice(deviceId: string) {
  try {
    const revoked = await trustStore.revoke(deviceId, new Date());
    if (revoked) {
      console.log(`Device ID ${deviceId} was successfully revoked.`);
    } else {
      console.log(`Device ID ${deviceId} not found.`);
    }
  } catch (err: any) {
    console.error("Failed to revoke device:", err.message);
  }
}

function installStartup() {
  console.log("Installing Automatic Startup Shortcut...");
  console.log("Explanation: This creates a batch command in your Windows Startup directory that runs 'npm run bridge:start' when you log in. It does not require Admin privileges.");
  
  const startupPath = getStartupFilePath();
  if (!startupPath) {
    console.error("Startup directory is only available on Windows HKCU/APPDATA environments.");
    process.exit(1);
  }
  
  const command = `@echo off\ncd /d "${join(projectRoot, "bridge")}"\nstart /b npm run bridge:start\n`;
  try {
    writeFileSync(startupPath, command, "utf8");
    console.log(`Startup script written successfully to: ${startupPath}`);
  } catch (err: any) {
    console.error("Failed to write startup script:", err.message);
  }
}

function removeStartup() {
  console.log("Removing Automatic Startup Shortcut...");
  const startupPath = getStartupFilePath();
  if (!startupPath) {
    console.error("Startup directory is only available on Windows.");
    process.exit(1);
  }
  
  if (existsSync(startupPath)) {
    try {
      unlinkSync(startupPath);
      console.log("Startup shortcut removed successfully.");
    } catch (err: any) {
      console.error("Failed to remove startup script:", err.message);
    }
  } else {
    console.log("Startup shortcut is not installed.");
  }
}

const args = process.argv.slice(2);
const cmd = args[0] || "pair";

if (cmd === "pair") {
  pair();
} else if (cmd === "doctor") {
  doctor();
} else if (cmd === "start") {
  startBridge();
} else if (cmd === "status") {
  status();
} else if (cmd === "stop") {
  stop();
} else if (cmd === "devices") {
  devices();
} else if (cmd === "revoke") {
  const id = args[1];
  if (!id) {
    console.error("Usage: npm run bridge:revoke-device <device-id>");
    process.exit(1);
  }
  revokeDevice(id);
} else if (cmd === "install-startup") {
  installStartup();
} else if (cmd === "remove-startup") {
  removeStartup();
} else {
  console.log("Unknown command.");
}
