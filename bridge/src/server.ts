import websocket from "@fastify/websocket";
import rateLimit from "@fastify/rate-limit";
import Fastify, { FastifyInstance } from "fastify";
import { WebSocket } from "ws";
import { fingerprint } from "./crypto.js";
import { PairingError, PairingManager } from "./pairing.js";
import {
  CreateTaskRequestSchema,
  ModelDescriptorSchema,
  SendTaskMessageRequestSchema,
  TaskIdParamsSchema,
  TrustDeviceRequestSchema,
  WorkspaceBrowseQuerySchema,
  WorkspaceCreateFolderRequestSchema,
  WorkspaceFileQuerySchema,
  WorkspaceImportImageRequestSchema,
  WorkspaceRoot
} from "./schemas.js";
import { MemoryTrustStore, TrustStore } from "./trust-store.js";
import { redactSensitive } from "./redaction.js";
import { WorkspaceBrowser, WorkspaceError } from "./workspace.js";
import { AntigravityAdapter, AntigravityCliAccountAdapter, UnsupportedCapabilityError } from "./antigravity-adapter.js";
import { BridgeAction, PermissionError, publicPermissionMatrix, requirePermission } from "./permissions.js";
import { readdir } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { z, ZodSchema } from "zod";

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
  const idempotency = new Map<string, Promise<unknown>>();
  
  // Share pairing manager if passed (crucial for local/LAN server split), otherwise create new
  const pairing = options.pairingManager ?? new PairingManager(trustStore, {
    address: options.address ?? "ws://127.0.0.1:59443",
    bridgeFingerprint: fingerprint(options.address ?? "maxgravity-local-bridge"),
    bridgeVersion: options.bridgeVersion ?? "0.1.0",
    clock: options.clock
  });

  const app = Fastify({
    https: options.https,
    bodyLimit: 15 * 1024 * 1024, // Allow up to 15MB for base64 image uploads from mobile
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
  app.get("/v1/connection/pending-devices", async (request, reply) => {
    if (!requireLocalRequest(request, reply)) {
      return;
    }
    return pairing.listPendingDevices();
  });

  app.post<{ Params: { id: string } }>("/v1/connection/pending-devices/:id/approve", async (request, reply) => {
    if (!requireLocalRequest(request, reply)) {
      return;
    }
    try {
      const result = await pairing.approvePendingDevice(request.params.id);
      return { status: "approved", device: result.device };
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

  app.post<{ Params: { id: string } }>("/v1/connection/pending-devices/:id/reject", async (request, reply) => {
    if (!requireLocalRequest(request, reply)) {
      return;
    }
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
    const auth = await authenticateRequest(pairing, request, reply, "devices.read");
    if (!auth) {
      return;
    }
    const devices = await trustStore.list();
    return devices.map(({ secretHash: _secretHash, ...device }) => device);
  });

  app.post<{ Params: { deviceId: string } }>("/v1/connection/trusted-devices/:deviceId/revoke", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "devices.revoke");
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
      { id: "workspace.roots", title: "Approved workspace roots", status: "Live", notes: "Root confinement is enforced." },
      { id: "permissions.roles", title: "Bridge role guards", status: "Live", notes: "Owner, Admin, Reviewer, Agent, and Viewer permissions are enforced on bridge endpoints." },
      { id: "models.contract", title: "Provider/model/runtime contract", status: "Live", notes: "Model payloads distinguish Provider, Model, and Agent Runtime." }
    ],
    permissions: publicPermissionMatrix(),
    antigravity: await adapter.getCapabilities()
  }));

  app.get("/v1/workspace/roots", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "workspace.read");
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
    const auth = await authenticateRequest(pairing, request, reply, "workspace.read");
    if (!auth) {
      return;
    }
    const parsed = parseRequest(WorkspaceBrowseQuerySchema, request.query, reply);
    if (!parsed) {
      return;
    }
    try {
      const nodes = await browser.browse(parsed.rootId, parsed.path);
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
    const auth = await authenticateRequest(pairing, request, reply, "workspace.read");
    if (!auth) {
      return;
    }
    const parsed = parseRequest(WorkspaceFileQuerySchema, request.query, reply);
    if (!parsed) {
      return;
    }
    try {
      return await browser.readTextFile(parsed.rootId, parsed.path);
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(error.code === "PATH_TRAVERSAL" ? 403 : 404).send({ error: error.code });
      }
      throw error;
    }
  });

  app.post<{ Body: { rootId: string; path: string; name: string } }>("/v1/workspace/create-folder", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "workspace.write");
    if (!auth) {
      return;
    }
    const parsed = parseRequest(WorkspaceCreateFolderRequestSchema, request.body, reply);
    if (!parsed) {
      return;
    }
    try {
      const relative = await browser.createFolder(parsed.rootId, parsed.path, parsed.name);
      return { status: "created", path: relative };
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(403).send({ error: error.code });
      }
      throw error;
    }
  });

  app.get("/v1/spaces", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "spaces.read");
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
    const auth = await authenticateRequest(pairing, request, reply, "workspace.write");
    if (!auth) {
      return;
    }
    const parsed = parseRequest(WorkspaceImportImageRequestSchema, request.body, reply);
    if (!parsed) {
      return;
    }
    try {
      if (!isProbablyBase64(parsed.base64Data)) {
        return reply.code(400).send({ error: "INVALID_REQUEST", message: "Image payload is invalid." });
      }
      const buffer = Buffer.from(parsed.base64Data, "base64");
      const savedPath = await browser.writeBinaryFile(parsed.rootId, parsed.path, parsed.fileName, buffer);
      return { status: "created", path: savedPath };
    } catch (error) {
      if (error instanceof WorkspaceError) {
        return reply.code(403).send({ error: error.code });
      }
      throw error;
    }
  });

  app.get("/v1/models", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "models.read");
    if (!auth) {
      return;
    }
    const models = await (adapter as AntigravityCliAccountAdapter).availableModels();
    return z.array(ModelDescriptorSchema).parse(models);
  });

  app.get("/v1/plugins", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "tools.read");
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
    const auth = await authenticateRequest(pairing, request, reply, "tools.read");
    if (!auth) {
      return;
    }
    return (adapter as AntigravityCliAccountAdapter).availableTools();
  });

  app.post("/v1/tasks", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "tasks.create");
    if (!auth) {
      return;
    }
    const body = parseRequest(CreateTaskRequestSchema, request.body, reply);
    if (!body) {
      return;
    }
    const key = idempotencyKey(request, body.clientRequestId, auth.id, "tasks.create");
    if (!key) {
      return reply.code(400).send({ error: "IDEMPOTENCY_KEY_REQUIRED", message: "A clientRequestId is required for task creation." });
    }

    return runIdempotent(idempotency, key, async () => {
      const title = body.title || firstLine(body.prompt) || "New task";
      const conv = await (adapter as AntigravityCliAccountAdapter).createConversation(body.spaceId, title, body.clientRequestId);
      await (adapter as AntigravityCliAccountAdapter).chat(conv.conversationId, body.prompt, body.workspaceRoot, body.selectedModelId);
      return conv;
    });
  });

  app.post<{ Params: { taskId: string } }>("/v1/tasks/:taskId/messages", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "tasks.message");
    if (!auth) {
      return;
    }
    const params = parseRequest(TaskIdParamsSchema, request.params, reply);
    const body = parseRequest(SendTaskMessageRequestSchema, request.body, reply);
    if (!params || !body) {
      return;
    }
    const key = idempotencyKey(request, body.clientRequestId, auth.id, `tasks.message:${params.taskId}`);
    if (key) {
      return runIdempotent(idempotency, key, async () => {
        await (adapter as AntigravityCliAccountAdapter).chat(params.taskId, body.prompt, body.workspaceRoot);
        return { status: "sent" };
      });
    }
    await (adapter as AntigravityCliAccountAdapter).chat(params.taskId, body.prompt, body.workspaceRoot);
    return { status: "sent" };
  });

  app.get<{ Params: { taskId: string } }>("/v1/tasks/:taskId", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply, "tasks.read");
    if (!auth) {
      return;
    }
    const params = parseRequest(TaskIdParamsSchema, request.params, reply);
    if (!params) {
      return;
    }
    const chats = await (adapter as AntigravityCliAccountAdapter).listConversations().catch(() => []);
    const chat = chats.find((c: any) => c.id === params.taskId);
    if (!chat) {
      return reply.code(404).send({ error: "CHAT_NOT_FOUND" });
    }
    return mapConversation(chat);
  });

  app.get("/v1/tasks/:taskId/events", { websocket: true }, async (socket: WebSocket, request) => {
    try {
      const device = await pairing.authenticate(
        String(request.headers["x-mg-device-id"] ?? ""),
        parseBearer(request.headers.authorization)
      );
      requirePermission(device, "tasks.read");
      
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
      return reply.code(501).send({ error: "UNSUPPORTED", message: error.message });
    }
    if (error instanceof PermissionError) {
      return reply.code(403).send({ error: "FORBIDDEN", message: "This trusted device is not allowed to perform that action." });
    }
    if (error instanceof z.ZodError) {
      return reply.code(500).send({ error: "CONTRACT_MISMATCH", message: "Bridge response did not match its public contract." });
    }
    const message = error instanceof Error ? error.message : String(error);
    _request.log.error({ error: redactSensitive(message) }, "Bridge request failed");
    return reply.code(500).send({ error: "INTERNAL_ERROR", message: "The bridge could not complete the request." });
  });

  return app;
}

async function authenticateRequest(pairing: PairingManager, request: any, reply: any, action?: BridgeAction): Promise<Awaited<ReturnType<PairingManager["authenticate"]>> | undefined> {
  try {
    const device = await pairing.authenticate(
      String(request.headers["x-mg-device-id"] ?? ""),
      parseBearer(request.headers.authorization)
    );
    if (action) {
      requirePermission(device, action);
    }
    return device;
  } catch (error) {
    if (error instanceof PermissionError) {
      reply.code(403).send({ error: "FORBIDDEN", message: "This trusted device is not allowed to perform that action." });
      return undefined;
    }
    sendPairingError(reply, error);
    return undefined;
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
    return reply.code(status).send({ error: error.code, message: permissionSafePairingMessage(error.code) });
  }
  throw error;
}

function parseRequest<T>(schema: ZodSchema<T>, input: unknown, reply: any): T | undefined {
  const parsed = schema.safeParse(input);
  if (parsed.success) {
    return parsed.data;
  }
  reply.code(400).send({
    error: "INVALID_REQUEST",
    message: "Request payload is invalid.",
    issues: parsed.error.issues.map((issue) => ({
      path: issue.path.join("."),
      message: issue.message
    }))
  });
  return undefined;
}

function requireLocalRequest(request: any, reply: any): boolean {
  const ip = String(request.ip ?? "");
  if (ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1") {
    return true;
  }
  reply.code(403).send({ error: "LOCAL_ONLY", message: "This bridge operation must be approved on the desktop." });
  return false;
}

function permissionSafePairingMessage(code: PairingError["code"]): string {
  switch (code) {
    case "DEVICE_UNKNOWN":
    case "DEVICE_SECRET_INVALID":
    case "DEVICE_REVOKED":
      return "Device authorization failed.";
    case "PAIRING_EXPIRED":
    case "PENDING_DEVICE_EXPIRED":
      return "Pairing expired. Start a new pairing session.";
    case "PAIRING_REPLAY":
      return "Pairing session was already used.";
    case "PAIRING_TOKEN_INVALID":
      return "Pairing code is invalid.";
    case "PENDING_DEVICE_NOT_FOUND":
      return "Pairing request was not found.";
    case "PAIRING_NOT_FOUND":
    default:
      return "Pairing session was not found.";
  }
}

function idempotencyKey(request: any, bodyKey: string | undefined, deviceId: string, operation: string): string | undefined {
  const headerKey = request.headers["x-mg-idempotency-key"];
  const raw = Array.isArray(headerKey) ? headerKey[0] : headerKey;
  const key = String(raw ?? bodyKey ?? "").trim();
  if (!key) {
    return undefined;
  }
  return `${deviceId}:${operation}:${key}`;
}

async function runIdempotent<T>(store: Map<string, Promise<unknown>>, key: string, operation: () => Promise<T>): Promise<T> {
  const existing = store.get(key);
  if (existing) {
    return (await existing) as T;
  }

  const pending = operation().finally(() => {
    setTimeout(() => store.delete(key), 60_000).unref();
  });
  store.set(key, pending);
  return pending;
}

function firstLine(value: string): string | undefined {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean)
    ?.slice(0, 180);
}

function isProbablyBase64(value: string): boolean {
  return /^[A-Za-z0-9+/]+={0,2}$/.test(value) && value.length % 4 === 0;
}

function mapConversation(c: any) {
  const transcript = readVisibleTranscript(c);
  const status = normalizeTaskStatus(c.status);
  const isRunning = isRunningStatus(status);
  const stateTone = toneForStatus(status);
  const messages = transcript.messages.length > 0 ? transcript.messages : [
    {
      id: `${c.id}-msg-user`,
      role: "user",
      body: c.prompt || `Start task: ${c.title}`,
      timestamp: c.createdAt,
      delivered: true,
      attachments: [] as any[]
    }
  ];

  const timeline = [...transcript.timeline];
  if (status === "Task completed") {
    timeline.push({
      id: `${c.id}-completed`,
      title: "Task completed",
      detail: "Agent completed the requested changes.",
      duration: "0s",
      tone: "good",
      isComplete: true
    });
  } else if (status === "Task failed") {
    timeline.push({
      id: `${c.id}-failed`,
      title: "Task failed",
      detail: safeUserDetail(c.lastError) || "Task execution failed.",
      duration: "0s",
      tone: "critical",
      isComplete: true
    });
  } else {
    timeline.push({
      id: `${c.id}-current`,
      title: status,
      detail: "Live step streamed from bridge.",
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
      stateText: status,
      stateTone: stateTone,
      messages: messages,
      timeline: timeline,
      files: transcript.files,
      diffs: transcript.diffs,
      commands: transcript.commands,
      approval: status === "Awaiting approval" ? {
        id: `${c.id}-approval`,
        title: "Approval required",
        summary: "Agent is awaiting permission to proceed.",
        scope: "Command/Write action",
        affectedItems: []
      } : null,
      completion: status === "Task completed" ? {
        summary: "Task finished successfully.",
        filesChanged: transcript.files.length,
        linesAdded: 0,
        linesRemoved: 0,
        checksRun: transcript.commands.map((cmd: any) => cmd.command),
        warnings: [],
        fullReply: transcript.fullReply || "The task was completed successfully."
      } : null
    }
  };
}

function readVisibleTranscript(c: any) {
  const output = {
    messages: [] as any[],
    timeline: [] as any[],
    files: [] as string[],
    diffs: [] as any[],
    commands: [] as any[],
    fullReply: ""
  };

  if (!c.realId) {
    return output;
  }

  const logFile = path.join(
    process.env.USERPROFILE ?? "C:\\Users\\kuroi",
    ".gemini",
    "antigravity",
    "brain",
    c.realId,
    ".system_generated",
    "logs",
    "transcript.jsonl"
  );
  if (!existsSync(logFile)) {
    return output;
  }

  try {
    const lines = readFileSync(logFile, "utf8").split(/\r?\n/).filter((line) => line.trim());
    for (const line of lines) {
      const step = JSON.parse(line);
      const timestamp = step.created_at || step.timestamp || c.createdAt;
      const stepIndex = String(step.step_index ?? output.timeline.length);

      if (step.source === "USER_EXPLICIT" && step.type === "USER_INPUT") {
        const body = visibleUserContent(step.content);
        if (body) {
          output.messages.push({
            id: `${c.id}-msg-user-${stepIndex}`,
            role: "user",
            body,
            timestamp,
            delivered: true,
            attachments: []
          });
        }
      }

      if (step.source === "MODEL" && step.type === "PLANNER_RESPONSE" && typeof step.content === "string" && step.content.trim()) {
        const body = safeUserDetail(step.content, 12_000);
        output.fullReply = body;
        output.messages.push({
          id: `${c.id}-msg-assistant-${stepIndex}`,
          role: "assistant",
          body,
          timestamp,
          delivered: true,
          attachments: []
        });
      }

      for (const toolCall of step.tool_calls ?? []) {
        const mapped = mapToolCall(c.id, stepIndex, toolCall);
        output.timeline.push(mapped.event);
        if (mapped.file && !output.files.includes(mapped.file)) {
          output.files.push(mapped.file);
        }
        if (mapped.command) {
          output.commands.push(mapped.command);
        }
      }
    }
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    output.timeline.push({
      id: `${c.id}-transcript-read-failed`,
      title: "Transcript unavailable",
      detail: safeUserDetail(detail),
      duration: "0s",
      tone: "warning",
      isComplete: true
    });
  }

  return output;
}

function visibleUserContent(raw: unknown): string {
  if (typeof raw !== "string") {
    return "";
  }
  const match = raw.match(/<USER_REQUEST>([\s\S]*?)<\/USER_REQUEST>/);
  return safeUserDetail((match ? match[1] : raw).trim(), 12_000);
}

function mapToolCall(taskId: string, stepIndex: string, toolCall: any) {
  const name = String(toolCall.name ?? "agent step");
  const args = toolCall.args ?? {};
  let title = name;
  let detail = "";
  let file: string | undefined;
  let command: any | undefined;

  if (name === "run_command") {
    title = "Running command";
    detail = String(args.CommandLine ?? args.command ?? "");
    command = {
      id: `${taskId}-cmd-${stepIndex}`,
      command: safeUserDetail(detail, 2_000),
      result: "Started",
      duration: "Live",
      output: "Command output is streamed through the bridge when available."
    };
  } else if (["view_file", "read_file", "view_file_content", "list_dir", "list_directory", "grep_search"].includes(name)) {
    title = "Reading workspace";
    detail = String(args.AbsolutePath ?? args.DirectoryPath ?? args.SearchPath ?? args.path ?? args.TargetFile ?? "");
    file = detail ? path.basename(detail) : undefined;
  } else if (["write_to_file", "replace_file_content", "multi_replace_file_content", "write_file", "edit_file", "create_file"].includes(name)) {
    title = "Applying changes";
    detail = String(args.TargetFile ?? args.path ?? "");
    file = detail ? path.basename(detail) : undefined;
  }

  return {
    file,
    command,
    event: {
      id: `${taskId}-event-${stepIndex}-${name}`,
      title,
      detail: safeUserDetail(detail || "Agent step in progress.", 300),
      duration: "Live",
      tone: "neutral",
      isComplete: true
    }
  };
}

function normalizeTaskStatus(status: unknown): string {
  const value = typeof status === "string" && status.trim() ? status.trim() : "Planning changes";
  if (value === "Running command") {
    return "Running commands";
  }
  if (value === "Reading workspace") {
    return "Reading files";
  }
  return value;
}

function isRunningStatus(status: string): boolean {
  return [
    "Starting Antigravity task",
    "Planning changes",
    "Reading files",
    "Checking workspace",
    "Updating styles",
    "Applying changes",
    "Running commands",
    "Running tests",
    "Awaiting approval",
    "Running task"
  ].includes(status);
}

function toneForStatus(status: string): string {
  if (status === "Task completed") {
    return "good";
  }
  if (status === "Task failed") {
    return "critical";
  }
  if (status === "Awaiting approval") {
    return "warning";
  }
  return "neutral";
}

function safeUserDetail(value: unknown, maxLength = 300): string {
  const text = typeof value === "string" ? value : String(value ?? "");
  return String(redactSensitive(text)).replace(/\s+/g, " ").trim().slice(0, maxLength);
}
