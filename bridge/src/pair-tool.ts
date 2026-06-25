import { exec, spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, "..", "..");
const localDir = join(projectRoot, "bridge", ".local");
const pidFile = join(localDir, "bridge.pid");
const port = Number(process.env.MAXGRAVITY_BRIDGE_PORT ?? "59443");

function getLocalIp(): string {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === "IPv4" && !iface.internal) {
        return iface.address;
      }
    }
  }
  return "127.0.0.1";
}

async function isBridgeRunning(): Promise<boolean> {
  if (!existsSync(pidFile)) return false;
  const pid = Number(readFileSync(pidFile, "utf8"));
  try {
    process.kill(pid, 0); // Check if process exists
    return true;
  } catch {
    return false;
  }
}

async function startBridge(): Promise<void> {
  const running = await isBridgeRunning();
  if (running) {
    console.log("Maxgravity Bridge is already running.");
    return;
  }

  console.log("Starting Maxgravity Bridge...");
  const child = spawn("npm", ["run", "dev"], {
    cwd: join(projectRoot, "bridge"),
    detached: true,
    stdio: "ignore"
  });
  child.unref();

  // Wait 2 seconds for server to start
  await new Promise(resolve => setTimeout(resolve, 2000));
}

async function getPairingSession() {
  const localIp = getLocalIp();
  const url = `http://127.0.0.1:${port}/v1/connection/pairing-sessions`;
  const response = await fetch(url, { method: "POST" });
  if (!response.ok) {
    throw new Error(`Failed to create pairing session: ${response.statusText}`);
  }
  const payload = await response.json() as any;
  // Override localhost address with real local IP for network accessibility
  payload.address = `wss://${localIp}:${port}`;
  return payload;
}

async function pair() {
  await startBridge();
  
  try {
    const session = await getPairingSession();
    const localIp = getLocalIp();
    const computerName = os.hostname();
    
    // Generate static HTML pairing page
    const htmlContent = `
<!DOCTYPE html>
<html>
<head>
  <title>Maxgravity Pairing Setup</title>
  <style>
    body {
      background-color: #000;
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
      background-color: #1a1a1c;
      border: 1px solid rgba(255,255,255,0.09);
      border-radius: 28px;
      padding: 40px;
      width: 420px;
      text-align: center;
      box-shadow: 0 20px 40px rgba(0,0,0,0.5);
    }
    h1 {
      font-size: 28px;
      font-weight: 700;
      margin: 10px 0;
    }
    .computer {
      font-size: 14px;
      color: rgba(255,255,255,0.66);
      background-color: rgba(255,255,255,0.06);
      padding: 6px 12px;
      border-radius: 20px;
      display: inline-block;
      margin-bottom: 20px;
    }
    .qr-container {
      background-color: #fff;
      padding: 20px;
      border-radius: 20px;
      display: inline-block;
      margin: 20px 0;
    }
    .countdown {
      font-size: 15px;
      color: #f4d029;
      font-weight: 600;
    }
    .status {
      margin-top: 20px;
      font-size: 15px;
      color: rgba(255,255,255,0.66);
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="computer">${computerName} (${localIp})</div>
    <h1>Connect Maxgravity</h1>
    <p style="font-size: 14px; color: rgba(255,255,255,0.66);">Scan this QR code from the Maxgravity app on your iPhone.</p>
    
    <div class="qr-container" id="qrcode"></div>
    
    <div class="countdown" id="countdown">Token expires in 5:00</div>
    <div class="status" id="status">Waiting for iPhone scan...</div>
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
        document.getElementById("countdown").style.color = "#ef3340";
        document.getElementById("status").innerText = "Please regenerate the pairing QR code.";
      } else {
        const mins = Math.floor(diff / 60000);
        const secs = Math.floor((diff % 60000) / 1000);
        document.getElementById("countdown").innerText = \`Token expires in \${mins}:\${secs < 10 ? '0' : ''}\${secs}\`;
      }
    }, 1000);

    // Poll trusted devices to see if new device was added
    const deviceId = payload.sessionId;
    const pollInterval = setInterval(async () => {
      try {
        const res = await fetch("http://127.0.0.1:${port}/v1/connection/health");
        if (res.ok) {
          // Check if devices list has changed or connection status changed
          // Since the client connects via trust endpoint, the desktop bridge saves trusted state
        }
      } catch (err) {}
    }, 3000);
  </script>
</body>
</html>
    `;

    const htmlPath = join(localDir, "pair.html");
    writeFileSync(htmlPath, htmlContent);
    console.log(`Generated pairing page at: ${htmlPath}`);

    // Open pairing page in default browser
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
  const running = await isBridgeRunning();
  if (!running) {
    console.log("Error: Bridge is offline. Start the bridge first.");
    return;
  }
  // Try finding trust store file directly to list devices
  const trustStoreFile = join(localDir, "trusted-devices.json");
  if (!existsSync(trustStoreFile)) {
    console.log("No trusted devices found.");
    return;
  }
  try {
    const devices = JSON.parse(readFileSync(trustStoreFile, "utf8"));
    console.log("Trusted Devices:");
    devices.forEach((d: any) => {
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
    console.error("Failed to read trusted devices store:", err.message);
  }
}

async function revokeDevice(deviceId: string) {
  const trustStoreFile = join(localDir, "trusted-devices.json");
  if (!existsSync(trustStoreFile)) {
    console.log("No trusted devices found.");
    return;
  }
  try {
    const devices = JSON.parse(readFileSync(trustStoreFile, "utf8"));
    const device = devices.find((d: any) => d.id === deviceId);
    if (!device) {
      console.log(`Device ID ${deviceId} not found.`);
      return;
    }
    device.revokedAt = new Date().toISOString();
    writeFileSync(trustStoreFile, JSON.stringify(devices, null, 2));
    console.log(`Device ${device.name} (ID: ${deviceId}) was successfully revoked.`);
  } catch (err: any) {
    console.error("Failed to revoke device:", err.message);
  }
}

const args = process.argv.slice(2);
const cmd = args[0] || "pair";

if (cmd === "pair") {
  pair();
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
} else {
  console.log("Unknown command.");
}
