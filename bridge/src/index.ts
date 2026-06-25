import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { buildServer } from "./server.js";
import { FileTrustStore } from "./trust-store.js";

import { writeFileSync, mkdirSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const localDir = join(here, "..", ".local");
mkdirSync(localDir, { recursive: true });
writeFileSync(join(localDir, "bridge.pid"), String(process.pid));

const trustStorePath = process.env.MAXGRAVITY_TRUST_STORE ?? join(localDir, "trusted-devices.json");
const port = Number(process.env.MAXGRAVITY_BRIDGE_PORT ?? "59443");
const host = process.env.MAXGRAVITY_BRIDGE_HOST ?? "127.0.0.1";

const server = await buildServer({
  trustStore: new FileTrustStore(trustStorePath),
  address: `wss://${host}:${port}`,
  bridgeVersion: "0.1.0"
});

await server.listen({ port, host });
