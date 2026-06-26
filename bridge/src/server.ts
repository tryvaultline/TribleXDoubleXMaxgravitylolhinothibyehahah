import websocket from "@fastify/websocket";
import rateLimit from "@fastify/rate-limit";
import Fastify, { FastifyInstance } from "fastify";
import { WebSocket } from "ws";
import { fingerprint } from "./crypto.js";
import { PairingError, PairingManager } from "./pairing.js";
import { TrustDeviceRequestSchema, WorkspaceRoot } from "./schemas.js";
import { MemoryTrustStore, TrustStore } from "./trust-store.js";
import { redactSensitive } from "./redaction.js";
import { WorkspaceBrowser, WorkspaceError } from "./workspace.js";
import { AntigravityAdapter, AntigravityCliAccountAdapter, UnsupportedCapabilityError } from "./antigravity-adapter.js";
import { readdir } from "node:fs/promises";
import path from "node:path";

interface BuildServerOptions {
  trustStore?: TrustStore;
  adapter?: AntigravityAdapter;
  workspaceRoots?: WorkspaceRoot[];
  address?: string;
  bridgeVersion?: string;
  clock?: () => Date;
  https?: { key: Buffer; cert: Buffer };
  pairingManager?: PairingManager;
  beforeCreatePairingSession?: () => Promise<void>;
}

export async function buildServer(options: BuildServerOptions = {}): Promise<FastifyInstance<any, any, any, any, any>> {
  const trustStore = options.trustStore ?? new MemoryTrustStore();
  const adapter = options.adapter ?? new AntigravityCliAccountAdapter();
  const browser = new WorkspaceBrowser(options.workspaceRoots ?? []);
  
  // Share pairing manager if passed (crucial for local/LAN server split), otherwise create new
  const pairing = options.pairingManager ?? new PairingManager(trustStore, {
    address: options.address ?? "ws://127.0.0.1:59443",
    bridgeFingerprint: fingerprint(options.address ?? "maxgravity-local-bridge"),
    bridgeVersion: options.bridgeVersion ?? "0.1.0",
    clock: options.clock
  });

  const app = Fastify({
    https: options.https,
    logger: {
      redact: ["req.headers.authorization", "token", "deviceSecret", "*.token", "*.secret"]
    }
  } as any);

  // Register plugins
  await app.register(websocket);
  await app.register(rateLimit, {
    global: false, // Apply rate limits explicitly on routes rather than globally
  });

  app.get("/v1/connection/health", async () => ({
    product: "Maxgravity Bridge",
    status: "Live",
    bridgeVersion: options.bridgeVersion ?? "0.1.0",
    time: new Date().toISOString()
  }));

  app.post("/v1/connection/pairing-sessions", {
    config: {
      rateLimit: {
        max: 5,
        timeWindow: "1 minute",
        errorResponseBuilder: () => ({ statusCode: 429, error: "RATE_LIMIT_EXCEEDED", message: "Too many pairing session requests." })
      }
    }
  }, async () => {
    if (options.beforeCreatePairingSession) {
      await options.beforeCreatePairingSession();
    }
    return pairing.createSession();
  });

  app.get("/v1/connection/active-session", async (request, reply) => {
    try {
      return pairing.getActiveSessionMetadata();
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

  // iPhone Registration Flow
  app.post("/v1/connection/trust/register", {
    config: {
      rateLimit: {
        max: 5,
        timeWindow: "1 minute",
        errorResponseBuilder: () => ({ statusCode: 429, error: "RATE_LIMIT_EXCEEDED", message: "Too many pairing registration attempts." })
      }
    }
  }, async (request, reply) => {
    const parsed = TrustDeviceRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "INVALID_REQUEST", detail: parsed.error.flatten() });
    }
    try {
      const clientIp = request.ip || "127.0.0.1";
      const pending = pairing.registerPendingDevice(parsed.data, clientIp);
      app.log.info({ pendingDeviceId: pending.id, clientIp }, "Pairing request registered");
      return reply.code(200).send({ status: "pending", pendingDeviceId: pending.id });
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

  // iPhone Status Polling Flow
  app.get<{ Querystring: { pendingDeviceId?: string } }>("/v1/connection/trust/status", {
    config: {
      rateLimit: {
        max: 120,
        timeWindow: "1 minute",
        errorResponseBuilder: () => ({ statusCode: 429, error: "RATE_LIMIT_EXCEEDED", message: "Too many status polls." })
      }
    }
  }, async (request, reply) => {
    const { pendingDeviceId } = request.query;
    if (!pendingDeviceId) {
      return reply.code(400).send({ error: "PENDING_DEVICE_ID_REQUIRED" });
    }
    try {
      const pending = pairing.getPendingDeviceStatus(pendingDeviceId);
      if (pending.status === "approved") {
        return {
          status: "approved",
          device: pending.trustedRecord,
          deviceSecret: pending.deviceSecret
        };
      }
      return { status: pending.status };
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

  // Local pairing approval routes
  app.get("/v1/connection/pending-devices", async () => {
    return pairing.listPendingDevices();
  });

  app.post<{ Params: { id: string } }>("/v1/connection/pending-devices/:id/approve", async (request, reply) => {
    try {
      const result = await pairing.approvePendingDevice(request.params.id);
      return { status: "approved", device: result.device };
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

  app.post<{ Params: { id: string } }>("/v1/connection/pending-devices/:id/reject", async (request, _reply) => {
    pairing.rejectPendingDevice(request.params.id);
    return { status: "rejected" };
  });

  // Backwards-compatible pairing endpoint
  app.post("/v1/connection/trust", {
    config: {
      rateLimit: {
        max: 5,
        timeWindow: "1 minute",
        errorResponseBuilder: () => ({ statusCode: 429, error: "RATE_LIMIT_EXCEEDED", message: "Too many pairing attempts." })
      }
    }
  }, async (request, reply) => {
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
      { id: "connection.qr-pairing", title: "QR pairing protocol", status: "Live", notes: "Expiring session, replay rejection, desktop approval, and trust registry are fully implemented." },
      { id: "workspace.roots", title: "Approved workspace roots", status: "Live", notes: "Root confinement is enforced." }
    ],
    antigravity: await adapter.getCapabilities()
  }));

  app.get("/v1/workspace/roots", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    return browser.listRoots().map((root) => ({
      id: root.id,
      name: root.name,
      path: root.path,
      isDirectory: true,
      children: []
    }));
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
      const nodes = await browser.browse(request.query.rootId, request.query.path ?? ".");
      return nodes.map((node) => ({
        id: node.path,
        name: node.name,
        path: node.path,
        isDirectory: node.isDirectory,
        children: []
      }));
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(error.code === "PATH_TRAVERSAL" ? 403 : 404).send({ error: error.code });
      }
      throw error;
    }
  });

  app.get<{ Querystring: { rootId?: string; path?: string } }>("/v1/workspace/file", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    if (!request.query.rootId || !request.query.path) {
      return reply.code(400).send({ error: "ROOT_AND_PATH_REQUIRED" });
    }
    try {
      return await browser.readTextFile(request.query.rootId, request.query.path);
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(error.code === "PATH_TRAVERSAL" ? 403 : 404).send({ error: error.code });
      }
      throw error;
    }
  });

  app.post<{ Body: { rootId: string; path: string; name: string } }>("/v1/workspace/create-folder", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const { rootId, path, name } = request.body;
    try {
      const relative = await browser.createFolder(rootId, path, name);
      return { status: "created", path: relative };
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(403).send({ error: error.code });
      }
      throw error;
    }
  });

  app.get("/v1/spaces", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const roots = browser.listRoots();
    const spaces = [];
    for (const root of roots) {
      const chats = await (adapter as AntigravityCliAccountAdapter).listConversations(root.id).catch(() => []);
      const mapped = chats.map(mapConversation);
      spaces.push({
        id: root.id,
        name: root.name,
        chats: mapped,
        isPinned: false,
        statusText: chats.some((c: any) => ["Planning changes", "Reading files", "Updating files", "Running commands", "Running tests", "Awaiting approval"].includes(c.status)) ? "Running" : null
      });
    }
    return spaces;
  });

  app.post<{ Body: { rootId: string; path: string; fileName: string; base64Data: string } }>("/v1/workspace/import-image", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const { rootId, path: relativePath, fileName, base64Data } = request.body;
    if (!rootId || !relativePath || !fileName || !base64Data) {
      return reply.code(400).send({ error: "INVALID_IMAGE_IMPORT_REQUEST" });
    }
    try {
      const buffer = Buffer.from(base64Data, "base64");
      const savedPath = await browser.writeBinaryFile(rootId, relativePath, fileName, buffer);
      return { status: "created", path: savedPath };
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(403).send({ error: error.code });
      }
      throw error;
    }
  });

  app.get("/v1/models", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    return (adapter as AntigravityCliAccountAdapter).availableModels();
  });

  app.get("/v1/plugins", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const extensionsDir = path.join(process.env.USERPROFILE ?? "C:\\Users\\kuroi", ".antigravity", "extensions");
    try {
      const entries = await readdir(extensionsDir, { withFileTypes: true });
      return entries
        .filter((entry) => entry.isDirectory())
        .map((entry) => ({
          id: entry.name,
          name: entry.name,
          path: path.join(extensionsDir, entry.name)
        }));
    } catch {
      return [];
    }
  });

  app.get("/v1/tools", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    return (adapter as AntigravityCliAccountAdapter).availableTools();
  });

  app.post("/v1/tasks", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const body = request.body as any;
    const { spaceId, title, prompt, workspaceRoot, selectedModelId } = body;
    const conv = await (adapter as AntigravityCliAccountAdapter).createConversation(spaceId, title || "New task");
    await (adapter as AntigravityCliAccountAdapter).chat(conv.conversationId, prompt, workspaceRoot, selectedModelId);
    return conv;
  });

  app.post<{ Params: { taskId: string } }>("/v1/tasks/:taskId/messages", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const body = request.body as any;
    const { prompt, workspaceRoot } = body;
    await (adapter as AntigravityCliAccountAdapter).chat(request.params.taskId, prompt, workspaceRoot);
    return { status: "sent" };
  });

  app.get<{ Params: { taskId: string } }>("/v1/tasks/:taskId", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const chats = await (adapter as AntigravityCliAccountAdapter).listConversations().catch(() => []);
    const chat = chats.find((c: any) => c.id === request.params.taskId);
    if (!chat) {
      return reply.code(404).send({ error: "CHAT_NOT_FOUND" });
    }
    return mapConversation(chat);
  });

  app.get("/v1/tasks/:taskId/events", { websocket: true }, async (socket: WebSocket, request) => {
    try {
      await pairing.authenticate(
        String(request.headers["x-mg-device-id"] ?? ""),
        parseBearer(request.headers.authorization)
      );
      
      const taskId = (request.params as { taskId: string }).taskId;
      
      const unsubscribe = (adapter as AntigravityCliAccountAdapter).onEvent((event: any) => {
        if (event.taskId === taskId) {
          socket.send(JSON.stringify(redactSensitive(event)));
        }
      });
      
      socket.on("close", () => {
        unsubscribe();
      });
    } catch {
      socket.close(1008, "Unauthorized");
    }
  });

  app.setErrorHandler((error: any, _request, reply) => {
    if (error.statusCode === 429 || error.error === "RATE_LIMIT_EXCEEDED") {
      const code = error.statusCode || 429;
      return reply.code(code).send({
        error: error.error || error.code || "RATE_LIMIT_EXCEEDED",
        message: error.message
      });
    }
    if (error.statusCode) {
      return reply.code(error.statusCode).send({
        error: error.code || "ERROR",
        message: error.message
      });
    }
    if (error instanceof UnsupportedCapabilityError) {
      return reply.code(501).send({ error: "UNSUPPORTED", detail: error.message });
    }
    const message = error instanceof Error ? error.message : String(error);
    return reply.code(500).send({ error: "INTERNAL_ERROR", detail: redactSensitive(message) });
  });

  return app;
}

async function authenticateRequest(pairing: PairingManager, request: any, reply: any): Promise<boolean> {
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

function sendPairingError(reply: any, error: unknown): any {
  if (error instanceof PairingError) {
    let status = 400;
    if (error.code === "DEVICE_UNKNOWN" || error.code === "DEVICE_SECRET_INVALID" || error.code === "DEVICE_REVOKED") {
      status = 401;
    }
    return reply.code(status).send({ error: error.code, detail: error.message });
  }
  throw error;
}

function mapConversation(c: any) {
  const isRunning = [
    "Planning changes",
    "Reading files",
    "Checking workspace",
    "Updating styles",
    "Applying changes",
    "Running commands",
    "Running tests",
    "Awaiting approval"
  ].includes(c.status);

  const timeline = [];
  let stateTone = "neutral";
  
  if (c.status === "Task completed") {
    stateTone = "good";
    timeline.push({
      id: `${c.id}-completed`,
      title: "Task completed",
      detail: "Agent completed the requested changes.",
      duration: "0s",
      tone: "good",
      isComplete: true
    });
  } else if (c.status === "Task failed") {
    stateTone = "critical";
    timeline.push({
      id: `${c.id}-failed`,
      title: "Task failed",
      detail: c.lastError || "Task execution failed.",
      duration: "0s",
      tone: "critical",
      isComplete: true
    });
  } else {
    stateTone = c.status === "Awaiting approval" ? "warning" : "neutral";
    timeline.push({
      id: `${c.id}-current`,
      title: c.status,
      detail: "Live step streamed from bridge...",
      duration: "Live",
      tone: stateTone,
      isComplete: false
    });
  }

  return {
    id: c.id,
    title: c.title,
    lastActivity: c.updatedAt,
    isRunning: isRunning,
    isPinned: false,
    thread: {
      id: c.id,
      title: c.title,
      stateText: c.status,
      stateTone: stateTone,
      messages: [
        {
          id: `${c.id}-msg-user`,
          role: "user",
          body: c.prompt || `Start task: ${c.title}`,
          timestamp: c.createdAt,
          delivered: true,
          attachments: []
        }
      ],
      timeline: timeline,
      files: [],
      diffs: [],
      commands: [],
      approval: c.status === "Awaiting approval" ? {
        id: `${c.id}-approval`,
        title: "Approval required",
        summary: "Agent is awaiting permission to proceed.",
        scope: "Command/Write action",
        affectedItems: []
      } : null,
      completion: c.status === "Task completed" ? {
        summary: "Task finished successfully.",
        filesChanged: 0,
        linesAdded: 0,
        linesRemoved: 0,
        checksRun: [],
        warnings: [],
        fullReply: "The task was completed successfully."
      } : null
    }
  };
}
