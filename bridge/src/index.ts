import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { buildServer } from "./server.js";
import { FileTrustStore } from "./trust-store.js";
import os from "node:os";

import { writeFileSync, mkdirSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const localDir = join(here, "..", ".local");
mkdirSync(localDir, { recursive: true });
writeFileSync(join(localDir, "bridge.pid"), String(process.pid));

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

const trustStorePath = process.env.MAXGRAVITY_TRUST_STORE ?? join(localDir, "trusted-devices.json");
const port = Number(process.env.MAXGRAVITY_BRIDGE_PORT ?? "59443");
const host = process.env.MAXGRAVITY_BRIDGE_HOST ?? "0.0.0.0";
const localIp = getLocalIp();

const projectRoot = join(here, "..", "..");
const server = await buildServer({
  trustStore: new FileTrustStore(trustStorePath),
  address: `ws://${localIp}:${port}`,
  bridgeVersion: "0.1.0",
  workspaceRoots: [
    {
      id: "maxgravity-project",
      name: "Maxgravity Workspace",
      path: projectRoot
    }
  ]
});

await server.listen({ port, host });
