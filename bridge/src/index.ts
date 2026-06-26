import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { buildServer } from "./server.js";
import { FileTrustStore } from "./trust-store.js";
import { getOrCreateCert } from "./security/certs.js";
import { PairingManager } from "./pairing.js";
import { getLocalIp } from "./security/network.js";
import { writeFileSync, mkdirSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const localDir = join(here, "..", ".local");
mkdirSync(localDir, { recursive: true });
writeFileSync(join(localDir, "bridge.pid"), String(process.pid));

const trustStorePath = process.env.MAXGRAVITY_TRUST_STORE ?? join(localDir, "trusted-devices.json");
const port = Number(process.env.MAXGRAVITY_BRIDGE_PORT ?? "59443");
const localIp = getLocalIp();
const projectRoot = join(here, "..", "..");

const trustStore = new FileTrustStore(trustStorePath);
const { cert, key, fingerprint } = getOrCreateCert(localDir);

const pairingManager = new PairingManager(trustStore, {
  address: `wss://${localIp}:${port}`,
  bridgeFingerprint: fingerprint,
  bridgeVersion: "0.1.0"
});

const workspaceRoots = [
  {
    id: "maxgravity-project",
    name: "Maxgravity Workspace",
    path: projectRoot
  }
];

// Start local HTTP server bound to 127.0.0.1
const localServer = await buildServer({
  trustStore,
  pairingManager,
  address: `ws://127.0.0.1:${port}`,
  bridgeVersion: "0.1.0",
  workspaceRoots
});

await localServer.listen({ port, host: "127.0.0.1" });
console.log(`Local HTTP Server listening on http://127.0.0.1:${port}`);

// Dynamic LAN HTTPS server management
let lanServer: any = null;

async function startLanServer() {
  if (lanServer || localIp === "127.0.0.1") return;
  console.log(`Starting LAN HTTPS Server on wss://${localIp}:${port}...`);
  try {
    lanServer = await buildServer({
      trustStore,
      pairingManager,
      address: `wss://${localIp}:${port}`,
      bridgeVersion: "0.1.0",
      workspaceRoots,
      https: { key, cert }
    });
    await lanServer.listen({ port, host: localIp });
    console.log(`LAN HTTPS Server listening on wss://${localIp}:${port}`);
  } catch (err: any) {
    console.error("Failed to start LAN HTTPS Server:", err.message);
  }
}

async function stopLanServer() {
  if (!lanServer) return;
  console.log("Stopping LAN HTTPS Server...");
  try {
    await lanServer.close();
    lanServer = null;
    console.log("LAN HTTPS Server stopped.");
  } catch (err: any) {
    console.error("Failed to stop LAN HTTPS Server:", err.message);
  }
}

// Auto-trigger LAN server startup if there are active trusted devices
const devices = await trustStore.list();
const hasActiveDevices = devices.some((d) => !d.revokedAt);
if (hasActiveDevices) {
  await startLanServer();
}

// Check for pairing session activation to start LAN server
// We hook into the session creation by polling the pairing manager status or setting up an interval
const checkInterval = setInterval(async () => {
  try {
    const active = pairingManager.getActiveSessionMetadata();
    if (active) {
      await startLanServer();
    }
  } catch {
    // No active session. If no active trusted devices, shut down the LAN server
    const currentDevices = await trustStore.list();
    const activeDevs = currentDevices.some((d) => !d.revokedAt);
    if (!activeDevs && lanServer) {
      await stopLanServer();
    }
  }
}, 5000);

process.on("SIGTERM", async () => {
  clearInterval(checkInterval);
  await stopLanServer();
  await localServer.close();
  process.exit(0);
});
process.on("SIGINT", async () => {
  clearInterval(checkInterval);
  await stopLanServer();
  await localServer.close();
  process.exit(0);
});
