import { describe, expect, it } from "vitest";
import { PairingManager } from "../src/pairing.js";
import { MemoryTrustStore } from "../src/trust-store.js";
import { getOrCreateCert } from "../src/security/certs.js";
import { isPrivateLanIp, getLocalIp } from "../src/security/network.js";
import { WorkspaceBrowser } from "../src/workspace.js";
import { buildServer } from "../src/server.js";
import path from "node:path";

describe("1. Security Pairing & Approvals", () => {
  it("forces desktop approval before a trusted session is issued", async () => {
    const store = new MemoryTrustStore();
    const manager = new PairingManager(store, {
      address: "wss://127.0.0.1:59443",
      bridgeFingerprint: "ABCD",
      bridgeVersion: "0.1.0"
    });

    const session = manager.createSession();
    
    // Register pending device
    const pending = manager.registerPendingDevice({
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Test iPhone",
      devicePublicKeyFingerprint: "TEST-FP"
    }, "192.168.1.50");

    expect(pending.status).toBe("pending");
    
    // Auth must fail since it is not approved yet
    await expect(manager.authenticate(pending.id, "some-secret")).rejects.toThrow();

    // List pending
    const list = manager.listPendingDevices();
    expect(list.some(p => p.id === pending.id)).toBe(true);

    // Approve
    const approved = await manager.approvePendingDevice(pending.id);
    expect(approved.device.name).toBe("Test iPhone");

    // Retrieve and verify status
    const status = manager.getPendingDeviceStatus(pending.id);
    expect(status.status).toBe("approved");
    expect(status.deviceSecret).toBe(approved.deviceSecret);

    // Now auth must succeed
    const auth = await manager.authenticate(approved.device.id, approved.deviceSecret);
    expect(auth.name).toBe("Test iPhone");
  });

  it("handles rejection flow correctly and burns the session", async () => {
    const store = new MemoryTrustStore();
    const manager = new PairingManager(store, {
      address: "wss://127.0.0.1:59443",
      bridgeFingerprint: "ABCD",
      bridgeVersion: "0.1.0"
    });

    const session = manager.createSession();
    
    const pending = manager.registerPendingDevice({
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Test iPhone",
      devicePublicKeyFingerprint: "TEST-FP"
    }, "192.168.1.50");

    manager.rejectPendingDevice(pending.id);

    const status = manager.getPendingDeviceStatus(pending.id);
    expect(status.status).toBe("rejected");

    // Approve should now fail
    await expect(manager.approvePendingDevice(pending.id)).rejects.toThrow();
  });

  it("rejects expired pairing sessions", async () => {
    let now = new Date("2026-06-26T12:00:00.000Z");
    const store = new MemoryTrustStore();
    const manager = new PairingManager(store, {
      address: "wss://127.0.0.1:59443",
      bridgeFingerprint: "ABCD",
      bridgeVersion: "0.1.0",
      ttlMs: 60_000,
      clock: () => now
    });

    const session = manager.createSession();
    
    // Fast forward clock past TTL
    now = new Date("2026-06-26T12:02:00.000Z");

    expect(() => {
      manager.registerPendingDevice({
        sessionId: session.sessionId,
        token: session.token,
        deviceName: "Expired iPhone",
        devicePublicKeyFingerprint: "TEST-FP"
      }, "192.168.1.50");
    }).toThrow();
  });

  it("rejects duplicate approval / replay attacks", async () => {
    const store = new MemoryTrustStore();
    const manager = new PairingManager(store, {
      address: "wss://127.0.0.1:59443",
      bridgeFingerprint: "ABCD",
      bridgeVersion: "0.1.0"
    });

    const session = manager.createSession();
    const pending = manager.registerPendingDevice({
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Test iPhone",
      devicePublicKeyFingerprint: "TEST-FP"
    }, "192.168.1.50");

    await manager.approvePendingDevice(pending.id);

    // Second approval must fail as pairing session is already consumed
    await expect(manager.approvePendingDevice(pending.id)).rejects.toThrow();
  });
});

describe("2. Network Exposure & Filtering", () => {
  it("only accepts private LAN IP ranges", () => {
    // Private ranges
    expect(isPrivateLanIp("192.168.1.1")).toBe(true);
    expect(isPrivateLanIp("10.0.0.123")).toBe(true);
    expect(isPrivateLanIp("172.16.50.88")).toBe(true);

    // Public / Loopback ranges
    expect(isPrivateLanIp("127.0.0.1")).toBe(false);
    expect(isPrivateLanIp("8.8.8.8")).toBe(false);
    expect(isPrivateLanIp("142.250.190.46")).toBe(false);
    expect(isPrivateLanIp("not-an-ip")).toBe(false);
  });

  it("correctly falls back or returns local interface", () => {
    const local = getLocalIp();
    expect(local).toBeDefined();
    // Should either be a valid private LAN IP or fallback loopback 127.0.0.1
    if (local !== "127.0.0.1") {
      expect(isPrivateLanIp(local)).toBe(true);
    }
  });
});

describe("3. Workspace Confinement", () => {
  it("prevents directory traversal escapes", () => {
    const rootPath = path.resolve(process.cwd());
    const browser = new WorkspaceBrowser([
      { id: "test-root", name: "Test Root", path: rootPath }
    ]);

    // Safe path resolution
    const resolvedSafe = browser.resolve("test-root", "src/pairing.ts");
    expect(resolvedSafe).toContain("pairing.ts");

    // Traversal attempts
    expect(() => {
      browser.resolve("test-root", "../../../Windows/System32");
    }).toThrowError(/escapes the approved workspace root/);

    expect(() => {
      browser.resolve("test-root", "/Windows/System32");
    }).toThrowError(/escapes the approved workspace root/);
  });
});

describe("4. TLS Certificates Fingerprinting", () => {
  it("generates certs and extracts a valid SHA-256 fingerprint", () => {
    const tempDir = path.join(process.cwd(), ".local");
    const certs = getOrCreateCert(tempDir);
    expect(certs.cert).toBeDefined();
    expect(certs.key).toBeDefined();
    expect(certs.fingerprint).toMatch(/^[0-9A-F]{64}$/); // SHA-256 fingerprint hex match
  });
});

describe("5. Rate Limiting", () => {
  it("throttles repeated pairing registration requests (rate limiting)", async () => {
    const app = await buildServer();
    let lastStatus = 0;
    
    // Inject 6 requests in a row to the register route. Max is configured as 5.
    for (let i = 0; i < 6; i++) {
      const res = await app.inject({
        method: "POST",
        url: "/v1/connection/trust/register",
        payload: {
          sessionId: "a".repeat(16),
          token: "b".repeat(24),
          deviceName: "Abuser",
          devicePublicKeyFingerprint: "BAD-FINGERPRINT"
        }
      });
      lastStatus = res.statusCode;
    }
    
    expect(lastStatus).toBe(429);
    await app.close();
  });
});
