import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server.js";

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
});
