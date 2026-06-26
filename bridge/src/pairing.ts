import { randomUUID } from "node:crypto";
import { randomToken, safeEqualHash, sha256 } from "./crypto.js";
import { PairingSessionPayload, TrustedDevice, TrustDeviceRequest } from "./schemas.js";
import { TrustStore } from "./trust-store.js";

type Clock = () => Date;

interface PairingRecord {
  sessionId: string;
  tokenHash: string;
  address: string;
  bridgeFingerprint: string;
  bridgeVersion: string;
  expiresAt: Date;
  consumedAt?: Date;
}

export interface TrustResult {
  device: Omit<TrustedDevice, "secretHash">;
  deviceSecret: string;
}

export interface PendingDevice {
  id: string;
  sessionId: string;
  deviceName: string;
  devicePlatform: string;
  clientIp: string;
  publicKeyFingerprint: string;
  expiresAt: Date;
  status: "pending" | "approved" | "rejected";
  deviceSecret?: string;
  trustedRecord?: Omit<TrustedDevice, "secretHash">;
}

export class PairingError extends Error {
  constructor(
    message: string,
    readonly code:
      | "PAIRING_NOT_FOUND"
      | "PAIRING_EXPIRED"
      | "PAIRING_REPLAY"
      | "PAIRING_TOKEN_INVALID"
      | "DEVICE_REVOKED"
      | "DEVICE_UNKNOWN"
      | "DEVICE_SECRET_INVALID"
      | "PENDING_DEVICE_NOT_FOUND"
      | "PENDING_DEVICE_EXPIRED"
  ) {
    super(message);
  }
}

export class PairingManager {
  private readonly sessions = new Map<string, PairingRecord>();
  private readonly pendingDevices = new Map<string, PendingDevice>();

  constructor(
    private readonly trustStore: TrustStore,
    private readonly options: {
      address: string;
      bridgeFingerprint: string;
      bridgeVersion: string;
      ttlMs?: number;
      clock?: Clock;
    }
  ) {}

  createSession(): PairingSessionPayload {
    const sessionId = randomToken(18);
    const token = randomToken(24);
    const now = this.now();
    const expiresAt = new Date(now.getTime() + (this.options.ttlMs ?? 5 * 60_000));
    const endpoint = new URL(this.options.address.replace(/^wss:/, "https:").replace(/^ws:/, "http:"));
    this.sessions.set(sessionId, {
      sessionId,
      tokenHash: sha256(token),
      address: this.options.address,
      bridgeFingerprint: this.options.bridgeFingerprint,
      bridgeVersion: this.options.bridgeVersion,
      expiresAt
    });

    return {
      protocolVersion: "1",
      sessionId,
      address: this.options.address,
      httpsHost: endpoint.hostname,
      httpsPort: Number(endpoint.port),
      wssPort: endpoint.protocol === "https:" ? Number(endpoint.port) : undefined,
      expiresAt: expiresAt.toISOString(),
      bridgeFingerprint: this.options.bridgeFingerprint,
      bridgeVersion: this.options.bridgeVersion,
      token
    };
  }

  getActiveSessionMetadata() {
    const now = this.now();
    for (const record of this.sessions.values()) {
      if (record.expiresAt.getTime() > now.getTime() && !record.consumedAt) {
        return {
          sessionId: record.sessionId,
          address: record.address,
          bridgeFingerprint: record.bridgeFingerprint,
          bridgeVersion: record.bridgeVersion,
          expiresAt: record.expiresAt.toISOString()
        };
      }
    }
    throw new PairingError("No active pairing session was found.", "PAIRING_NOT_FOUND");
  }

  registerPendingDevice(request: TrustDeviceRequest & { platform?: string }, clientIp: string): PendingDevice {
    const record = this.sessions.get(request.sessionId);
    if (!record) {
      throw new PairingError("Pairing session was not found.", "PAIRING_NOT_FOUND");
    }
    const now = this.now();
    if (record.consumedAt) {
      throw new PairingError("Pairing session was already consumed.", "PAIRING_REPLAY");
    }
    if (record.expiresAt.getTime() <= now.getTime()) {
      throw new PairingError("Pairing session expired.", "PAIRING_EXPIRED");
    }
    if (request.token && !safeEqualHash(request.token, record.tokenHash)) {
      throw new PairingError("Pairing token is invalid.", "PAIRING_TOKEN_INVALID");
    }

    const pendingId = randomUUID();
    const expiresAt = new Date(now.getTime() + 5 * 60_000); // 5 min TTL
    const pending: PendingDevice = {
      id: pendingId,
      sessionId: request.sessionId,
      deviceName: request.deviceName,
      devicePlatform: request.platform || "iOS",
      clientIp,
      publicKeyFingerprint: request.devicePublicKeyFingerprint,
      expiresAt,
      status: "pending"
    };

    this.pendingDevices.set(pendingId, pending);
    return pending;
  }

  getPendingDeviceStatus(pendingDeviceId: string): PendingDevice {
    const pending = this.pendingDevices.get(pendingDeviceId);
    if (!pending) {
      throw new PairingError("Pending device request not found.", "PENDING_DEVICE_NOT_FOUND");
    }
    const now = this.now();
    if (pending.status === "pending" && pending.expiresAt.getTime() <= now.getTime()) {
      pending.status = "rejected"; // Expired requests become rejected
      throw new PairingError("Pending device request expired.", "PENDING_DEVICE_EXPIRED");
    }
    return pending;
  }

  listPendingDevices(): PendingDevice[] {
    const now = this.now();
    return Array.from(this.pendingDevices.values()).filter(
      (p) => p.status === "pending" && p.expiresAt.getTime() > now.getTime()
    );
  }

  async approvePendingDevice(pendingDeviceId: string): Promise<TrustResult> {
    const pending = this.pendingDevices.get(pendingDeviceId);
    if (!pending) {
      throw new PairingError("Pending device request not found.", "PENDING_DEVICE_NOT_FOUND");
    }
    const now = this.now();
    if (pending.expiresAt.getTime() <= now.getTime()) {
      pending.status = "rejected";
      throw new PairingError("Pending device request expired.", "PENDING_DEVICE_EXPIRED");
    }
    if (pending.status !== "pending") {
      throw new PairingError("Pending device request is not pending.", "PAIRING_REPLAY");
    }

    const record = this.sessions.get(pending.sessionId);
    if (!record || record.consumedAt) {
      pending.status = "rejected";
      throw new PairingError("Pairing session already consumed or missing.", "PAIRING_REPLAY");
    }

    record.consumedAt = now;
    const deviceSecret = randomToken(32);
    const device: TrustedDevice = {
      id: randomUUID(),
      name: pending.deviceName,
      publicKeyFingerprint: pending.publicKeyFingerprint,
      pairedAt: now.toISOString(),
      secretHash: sha256(deviceSecret)
    };

    await this.trustStore.save(device);

    const publicDevice = {
      id: device.id,
      name: device.name,
      publicKeyFingerprint: device.publicKeyFingerprint,
      pairedAt: device.pairedAt,
      revokedAt: device.revokedAt
    };

    pending.status = "approved";
    pending.deviceSecret = deviceSecret;
    pending.trustedRecord = publicDevice;

    return { device: publicDevice, deviceSecret };
  }

  rejectPendingDevice(pendingDeviceId: string): void {
    const pending = this.pendingDevices.get(pendingDeviceId);
    if (pending) {
      pending.status = "rejected";
      const record = this.sessions.get(pending.sessionId);
      if (record) {
        record.consumedAt = this.now(); // Burn the pairing session
      }
    }
  }

  // Backwards compatibility helper for existing direct trust tests
  async trustDevice(request: TrustDeviceRequest): Promise<TrustResult> {
    const pending = this.registerPendingDevice(request, "127.0.0.1");
    return this.approvePendingDevice(pending.id);
  }

  async authenticate(deviceId: string | undefined, deviceSecret: string | undefined): Promise<TrustedDevice> {
    if (!deviceId || !deviceSecret) {
      throw new PairingError("Device credentials are required.", "DEVICE_UNKNOWN");
    }
    const device = await this.trustStore.find(deviceId);
    if (!device) {
      throw new PairingError("Unknown device.", "DEVICE_UNKNOWN");
    }
    if (device.revokedAt) {
      throw new PairingError("Device has been revoked.", "DEVICE_REVOKED");
    }
    if (!safeEqualHash(deviceSecret, device.secretHash)) {
      throw new PairingError("Device secret is invalid.", "DEVICE_SECRET_INVALID");
    }
    return device;
  }

  private now(): Date {
    return this.options.clock?.() ?? new Date();
  }
}
