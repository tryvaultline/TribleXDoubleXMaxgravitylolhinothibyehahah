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
  ) {
    super(message);
  }
}

export class PairingManager {
  private readonly sessions = new Map<string, PairingRecord>();

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
    this.sessions.set(sessionId, {
      sessionId,
      tokenHash: sha256(token),
      address: this.options.address,
      bridgeFingerprint: this.options.bridgeFingerprint,
      bridgeVersion: this.options.bridgeVersion,
      expiresAt
    });

    return {
      sessionId,
      address: this.options.address,
      token,
      expiresAt: expiresAt.toISOString(),
      bridgeFingerprint: this.options.bridgeFingerprint,
      bridgeVersion: this.options.bridgeVersion
    };
  }

  async trustDevice(request: TrustDeviceRequest): Promise<TrustResult> {
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
    if (!safeEqualHash(request.token, record.tokenHash)) {
      throw new PairingError("Pairing token is invalid.", "PAIRING_TOKEN_INVALID");
    }

    record.consumedAt = now;
    const deviceSecret = randomToken(32);
    const device: TrustedDevice = {
      id: randomUUID(),
      name: request.deviceName,
      publicKeyFingerprint: request.devicePublicKeyFingerprint,
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
    return { device: publicDevice, deviceSecret };
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
