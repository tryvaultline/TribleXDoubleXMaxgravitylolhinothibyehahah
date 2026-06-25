import { describe, expect, it } from "vitest";
import { PairingError, PairingManager } from "../src/pairing.js";
import { MemoryTrustStore } from "../src/trust-store.js";

function createManager(clock: () => Date = () => new Date("2026-06-25T12:00:00.000Z")) {
  const store = new MemoryTrustStore();
  const manager = new PairingManager(store, {
    address: "wss://127.0.0.1:59443",
    bridgeFingerprint: "ABCDEF123456",
    bridgeVersion: "0.1.0",
    ttlMs: 60_000,
    clock
  });
  return { manager, store };
}

describe("PairingManager", () => {
  it("trusts a device with a valid one-time token", async () => {
    const { manager, store } = createManager();
    const session = manager.createSession();

    const result = await manager.trustDevice({
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Kuroi iPhone",
      devicePublicKeyFingerprint: "IPHONE-FP-1"
    });

    expect(result.device.name).toBe("Kuroi iPhone");
    expect(result.deviceSecret.length).toBeGreaterThan(20);
    expect(await store.find(result.device.id)).toBeDefined();
  });

  it("rejects expired pairing tokens", async () => {
    let now = new Date("2026-06-25T12:00:00.000Z");
    const { manager } = createManager(() => now);
    const session = manager.createSession();
    now = new Date("2026-06-25T12:02:00.000Z");

    await expect(
      manager.trustDevice({
        sessionId: session.sessionId,
        token: session.token,
        deviceName: "Expired iPhone",
        devicePublicKeyFingerprint: "IPHONE-FP-2"
      })
    ).rejects.toMatchObject({ code: "PAIRING_EXPIRED" satisfies PairingError["code"] });
  });

  it("rejects replay of a consumed token", async () => {
    const { manager } = createManager();
    const session = manager.createSession();
    const request = {
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Kuroi iPhone",
      devicePublicKeyFingerprint: "IPHONE-FP-1"
    };

    await manager.trustDevice(request);
    await expect(manager.trustDevice(request)).rejects.toMatchObject({ code: "PAIRING_REPLAY" satisfies PairingError["code"] });
  });

  it("rejects unknown, revoked, and invalid device credentials", async () => {
    const { manager, store } = createManager();
    const session = manager.createSession();
    const { device, deviceSecret } = await manager.trustDevice({
      sessionId: session.sessionId,
      token: session.token,
      deviceName: "Kuroi iPhone",
      devicePublicKeyFingerprint: "IPHONE-FP-1"
    });

    await expect(manager.authenticate("unknown", deviceSecret)).rejects.toMatchObject({ code: "DEVICE_UNKNOWN" satisfies PairingError["code"] });
    await expect(manager.authenticate(device.id, "wrong")).rejects.toMatchObject({ code: "DEVICE_SECRET_INVALID" satisfies PairingError["code"] });
    await store.revoke(device.id, new Date("2026-06-25T12:01:00.000Z"));
    await expect(manager.authenticate(device.id, deviceSecret)).rejects.toMatchObject({ code: "DEVICE_REVOKED" satisfies PairingError["code"] });
  });
});
