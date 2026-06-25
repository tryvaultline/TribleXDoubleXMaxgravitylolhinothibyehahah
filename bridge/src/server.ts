import websocket from "@fastify/websocket";
import Fastify, { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { WebSocket } from "ws";
import { fingerprint } from "./crypto.js";
import { PairingError, PairingManager } from "./pairing.js";
import { BridgeEventSchema, TrustDeviceRequestSchema, WorkspaceRoot } from "./schemas.js";
import { MemoryTrustStore, TrustStore } from "./trust-store.js";
import { redactSensitive } from "./redaction.js";
import { WorkspaceBrowser, WorkspaceError } from "./workspace.js";
import { AntigravityAdapter, OfficialAntigravityAdapterPlaceholder, UnsupportedCapabilityError } from "./antigravity-adapter.js";

interface BuildServerOptions {
  trustStore?: TrustStore;
  adapter?: AntigravityAdapter;
  workspaceRoots?: WorkspaceRoot[];
  address?: string;
  bridgeVersion?: string;
  clock?: () => Date;
}

export async function buildServer(options: BuildServerOptions = {}): Promise<FastifyInstance> {
  const trustStore = options.trustStore ?? new MemoryTrustStore();
  const adapter = options.adapter ?? new OfficialAntigravityAdapterPlaceholder();
  const browser = new WorkspaceBrowser(options.workspaceRoots ?? []);
  const pairing = new PairingManager(trustStore, {
    address: options.address ?? "wss://127.0.0.1:59443",
    bridgeFingerprint: fingerprint(options.address ?? "maxgravity-local-bridge"),
    bridgeVersion: options.bridgeVersion ?? "0.1.0",
    clock: options.clock
  });

  const app = Fastify({
    logger: {
      redact: ["req.headers.authorization", "token", "deviceSecret", "*.token", "*.secret"]
    }
  });

  await app.register(websocket);

  app.get("/v1/connection/health", async () => ({
    product: "Maxgravity Bridge",
    status: "Live",
    bridgeVersion: options.bridgeVersion ?? "0.1.0",
    time: new Date().toISOString()
  }));

  app.post("/v1/connection/pairing-sessions", async () => pairing.createSession());

  app.post("/v1/connection/trust", async (request, reply) => {
    const parsed = TrustDeviceRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "INVALID_REQUEST", detail: parsed.error.flatten() });
    }
    try {
      return await pairing.trustDevice(parsed.data);
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

  app.get("/v1/connection/trusted-devices", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const devices = await trustStore.list();
    return devices.map(({ secretHash: _secretHash, ...device }) => device);
  });

  app.post<{ Params: { deviceId: string } }>("/v1/connection/trusted-devices/:deviceId/revoke", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const revoked = await trustStore.revoke(request.params.deviceId, new Date());
    return revoked ? { status: "revoked" } : reply.code(404).send({ error: "DEVICE_NOT_FOUND" });
  });

  app.get("/v1/capabilities", async () => ({
    bridge: [
      { id: "connection.health", title: "Connection health", status: "Live", notes: "Local Fastify health endpoint is implemented." },
      { id: "connection.qr-pairing", title: "QR pairing protocol", status: "Partial", notes: "Expiring session, replay rejection, trust registry, and auth are implemented. Camera UI and desktop confirmation are app-side/external." },
      { id: "workspace.roots", title: "Approved workspace roots", status: "Partial", notes: "Root confinement is implemented; roots must be configured by the desktop bridge." }
    ],
    antigravity: await adapter.getCapabilities()
  }));

  app.get("/v1/workspace/roots", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    return browser.listRoots();
  });

  app.get<{ Querystring: { rootId?: string; path?: string } }>("/v1/workspace/browse", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    if (!request.query.rootId) {
      return reply.code(400).send({ error: "ROOT_REQUIRED" });
    }
    try {
      return await browser.browse(request.query.rootId, request.query.path ?? ".");
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(error.code === "PATH_TRAVERSAL" ? 403 : 404).send({ error: error.code });
      }
      throw error;
    }
  });

  app.get("/v1/tasks/:taskId/events", { websocket: true }, async (socket: WebSocket, request) => {
    try {
      await pairing.authenticate(
        String(request.headers["x-mg-device-id"] ?? ""),
        parseBearer(request.headers.authorization)
      );
      const event = BridgeEventSchema.parse({
        type: "task.stage",
        taskId: (request.params as { taskId: string }).taskId,
        stage: "Checking workspace",
        detail: "WebSocket transport is authenticated; official Antigravity streaming is not connected yet.",
        emittedAt: new Date().toISOString()
      });
      socket.send(JSON.stringify(redactSensitive(event)));
    } catch {
      socket.close(1008, "Unauthorized");
    }
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof UnsupportedCapabilityError) {
      return reply.code(501).send({ error: "UNSUPPORTED", detail: error.message });
    }
    const message = error instanceof Error ? error.message : String(error);
    return reply.code(500).send({ error: "INTERNAL_ERROR", detail: redactSensitive(message) });
  });

  return app;
}

async function authenticateRequest(pairing: PairingManager, request: FastifyRequest, reply: FastifyReply): Promise<boolean> {
  try {
    await pairing.authenticate(
      String(request.headers["x-mg-device-id"] ?? ""),
      parseBearer(request.headers.authorization)
    );
    return true;
  } catch (error) {
    sendPairingError(reply, error);
    return false;
  }
}

function parseBearer(header: string | undefined): string | undefined {
  if (!header?.startsWith("Bearer ")) {
    return undefined;
  }
  return header.slice("Bearer ".length);
}

function sendPairingError(reply: FastifyReply, error: unknown): FastifyReply {
  if (error instanceof PairingError) {
    const status = error.code === "DEVICE_UNKNOWN" || error.code === "DEVICE_SECRET_INVALID" || error.code === "DEVICE_REVOKED" ? 401 : 400;
    return reply.code(status).send({ error: error.code, detail: error.message });
  }
  throw error;
}
