import websocket from "@fastify/websocket";
import Fastify, { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { WebSocket } from "ws";
import { fingerprint } from "./crypto.js";
import { PairingError, PairingManager } from "./pairing.js";
import { TrustDeviceRequestSchema, WorkspaceRoot } from "./schemas.js";
import { MemoryTrustStore, TrustStore } from "./trust-store.js";
import { redactSensitive } from "./redaction.js";
import { WorkspaceBrowser, WorkspaceError } from "./workspace.js";
import { AntigravityAdapter, AntigravityCliAccountAdapter, UnsupportedCapabilityError } from "./antigravity-adapter.js";

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
  const adapter = options.adapter ?? new AntigravityCliAccountAdapter();
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

  app.get("/v1/connection/active-session", async (request, reply) => {
    try {
      return pairing.getActiveSessionMetadata();
    } catch (error) {
      return sendPairingError(reply, error);
    }
  });

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

  app.post("/v1/tasks", async (request, reply) => {
    const auth = await authenticateRequest(pairing, request, reply);
    if (!auth) {
      return;
    }
    const body = request.body as any;
    const { spaceId, title, prompt, workspaceRoot } = body;
    

    const conv = await (adapter as AntigravityCliAccountAdapter).createConversation(spaceId, title || "New task");
    await (adapter as AntigravityCliAccountAdapter).chat(conv.conversationId, prompt, workspaceRoot);
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
      detail: "Task execution failed.",
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
          body: `Start task: ${c.title}`,
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
