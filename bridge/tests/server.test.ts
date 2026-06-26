import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server.js";
import { MemoryTrustStore } from "../src/trust-store.js";

async function pair(app: Awaited<ReturnType<typeof buildServer>>) {
  const sessionResponse = await app.inject({ method: "POST", url: "/v1/connection/pairing-sessions" });
  const session = sessionResponse.json();
  const trustResponse = await app.inject({
    method: "POST",
    url: "/v1/connection/trust",
    payload: {
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Kuroi iPhone",
      devicePublicKeyFingerprint: "IPHONE-FP-1"
    }
  });
  return trustResponse.json() as { device: { id: string }; deviceSecret: string };
}

describe("bridge server", () => {
  it("serves health without device trust", async () => {
    const app = await buildServer();
    const response = await app.inject({ method: "GET", url: "/v1/connection/health" });

    expect(response.statusCode).toBe(200);
    expect(response.json().product).toBe("Maxgravity Bridge");
    await app.close();
  });

  it("requires trusted device credentials for workspace roots", async () => {
    const app = await buildServer({ workspaceRoots: [{ id: "root", name: "Root", path: process.cwd() }] });
    const denied = await app.inject({ method: "GET", url: "/v1/workspace/roots" });

    expect(denied.statusCode).toBe(401);

    const trusted = await pair(app);
    const allowed = await app.inject({
      method: "GET",
      url: "/v1/workspace/roots",
      headers: {
        "x-mg-device-id": trusted.device.id,
        authorization: `Bearer ${trusted.deviceSecret}`
      }
    });

    expect(allowed.statusCode).toBe(200);
    expect(allowed.json()).toHaveLength(1);
    await app.close();
  });

  it("does not create a QR pairing session until the TLS readiness hook succeeds", async () => {
    let readinessChecks = 0;
    const app = await buildServer({
      beforeCreatePairingSession: async () => {
        readinessChecks += 1;
      }
    });

    const response = await app.inject({
      method: "POST",
      url: "/v1/connection/pairing-sessions",
      payload: {}
    });

    expect(response.statusCode).toBe(200);
    expect(readinessChecks).toBe(1);
    expect(response.json().address).toMatch(/^ws:\/\/|^wss:\/\//);
    await app.close();
  });

  it("returns Antigravity provider/model/runtime descriptors without Google or Gemini labels", async () => {
    const adapter = {
      async getCapabilities() {
        return [];
      },
      async diagnose() {
        return {};
      },
      async createConversation() {
        return {};
      },
      async chat() {
        return {};
      },
      async listConversations() {
        return [];
      },
      onEvent() {
        return () => undefined;
      },
      async availableModels() {
        return [
          {
            id: "antigravity-fast",
            name: "Antigravity Fast",
            description: "Provider: Antigravity. Model: Fast. Runtime: Antigravity Agent CLI.",
            provider: { id: "antigravity", name: "Antigravity" },
            model: { id: "flash", name: "Fast" },
            agentRuntime: { id: "antigravity-agent-cli", name: "Antigravity Agent CLI", status: "Live" },
            speed: "Fast",
            effort: "Balanced",
            capabilities: ["Chat"],
            isRecommended: true,
            state: "live"
          }
        ];
      },
      async availableTools() {
        return [];
      }
    };
    const app = await buildServer({ adapter: adapter as any });
    const trusted = await pair(app);
    const response = await app.inject({
      method: "GET",
      url: "/v1/models",
      headers: {
        "x-mg-device-id": trusted.device.id,
        authorization: `Bearer ${trusted.deviceSecret}`
      }
    });

    expect(response.statusCode).toBe(200);
    const models = response.json();
    expect(models.length).toBeGreaterThan(0);
    expect(JSON.stringify(models)).not.toMatch(/Gemini|Google/i);
    expect(models[0].provider.name).toBe("Antigravity");
    expect(models[0].agentRuntime.name).toBe("Antigravity Agent CLI");
    await app.close();
  });

  it("deduplicates repeated task creation requests with the same clientRequestId", async () => {
    let createCount = 0;
    let chatCount = 0;
    const adapter = {
      async getCapabilities() {
        return [];
      },
      async diagnose() {
        return {};
      },
      async createConversation(spaceId: string, title: string, conversationId?: string) {
        createCount += 1;
        return { conversationId: conversationId ?? "generated-id", spaceId, title, status: "Starting Antigravity task" };
      },
      async chat() {
        chatCount += 1;
        return { status: "started" };
      },
      async listConversations() {
        return [];
      },
      onEvent() {
        return () => undefined;
      },
      async availableModels() {
        return [];
      },
      async availableTools() {
        return [];
      }
    };
    const app = await buildServer({ adapter: adapter as any });
    const trusted = await pair(app);
    const headers = {
      "x-mg-device-id": trusted.device.id,
      authorization: `Bearer ${trusted.deviceSecret}`
    };
    const payload = {
      spaceId: "space",
      title: "Task",
      prompt: "Run one task",
      workspaceRoot: process.cwd(),
      selectedModelId: "antigravity-fast",
      clientRequestId: "ios-request-123456"
    };

    const first = await app.inject({ method: "POST", url: "/v1/tasks", headers, payload });
    const second = await app.inject({ method: "POST", url: "/v1/tasks", headers, payload });

    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);
    expect(first.json()).toEqual(second.json());
    expect(createCount).toBe(1);
    expect(chatCount).toBe(1);
    await app.close();
  });

  it("enforces trusted-device roles on sensitive task actions", async () => {
    const trustStore = new MemoryTrustStore();
    const app = await buildServer({ trustStore });
    const trusted = await pair(app);
    const devices = await trustStore.list();
    await trustStore.save({ ...devices[0], role: "Viewer" });

    const response = await app.inject({
      method: "POST",
      url: "/v1/tasks",
      headers: {
        "x-mg-device-id": trusted.device.id,
        authorization: `Bearer ${trusted.deviceSecret}`
      },
      payload: {
        spaceId: "space",
        prompt: "This should be denied",
        workspaceRoot: process.cwd(),
        clientRequestId: "viewer-denied-123"
      }
    });

    expect(response.statusCode).toBe(403);
    expect(response.json().error).toBe("FORBIDDEN");
    await app.close();
  });
});
