import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { TrustedDevice } from "./schemas.js";
import { protectForCurrentUser, unprotectForCurrentUser } from "./security/dpapi.js";

export interface TrustStore {
  list(): Promise<TrustedDevice[]>;
  find(deviceId: string): Promise<TrustedDevice | undefined>;
  save(device: TrustedDevice): Promise<void>;
  revoke(deviceId: string, revokedAt: Date): Promise<boolean>;
}

export class MemoryTrustStore implements TrustStore {
  private readonly devices = new Map<string, TrustedDevice>();

  async list(): Promise<TrustedDevice[]> {
    return [...this.devices.values()];
  }

  async find(deviceId: string): Promise<TrustedDevice | undefined> {
    return this.devices.get(deviceId);
  }

  async save(device: TrustedDevice): Promise<void> {
    this.devices.set(device.id, device);
  }

  async revoke(deviceId: string, revokedAt: Date): Promise<boolean> {
    const device = this.devices.get(deviceId);
    if (!device) {
      return false;
    }
    this.devices.set(deviceId, { ...device, revokedAt: revokedAt.toISOString() });
    return true;
  }
}

export class FileTrustStore implements TrustStore {
  constructor(private readonly filePath: string) {}

  async list(): Promise<TrustedDevice[]> {
    try {
      const data = await readFile(this.filePath, "utf8");
      const trimmed = data.trim();
      if (!trimmed) {
        return [];
      }
      // Safe migration check
      if (trimmed.startsWith("[")) {
        const devices = JSON.parse(trimmed) as TrustedDevice[];
        // Migrate to encrypted format
        await this.write(devices);
        return devices;
      }
      const decrypted = unprotectForCurrentUser(trimmed);
      return JSON.parse(decrypted) as TrustedDevice[];
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        return [];
      }
      console.error("CRITICAL: Failed to read or decrypt trusted devices store:", error);
      return [];
    }
  }

  async find(deviceId: string): Promise<TrustedDevice | undefined> {
    return (await this.list()).find((device) => device.id === deviceId);
  }

  async save(device: TrustedDevice): Promise<void> {
    const devices = (await this.list()).filter((existing) => existing.id !== device.id);
    devices.push(device);
    await this.write(devices);
  }

  async revoke(deviceId: string, revokedAt: Date): Promise<boolean> {
    let found = false;
    const devices = (await this.list()).map((device) => {
      if (device.id !== deviceId) {
        return device;
      }
      found = true;
      return { ...device, revokedAt: revokedAt.toISOString() };
    });
    await this.write(devices);
    return found;
  }

  private async write(devices: TrustedDevice[]): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    const plainText = JSON.stringify(devices, null, 2);
    const encrypted = protectForCurrentUser(plainText);
    await writeFile(this.filePath, encrypted, { encoding: "utf8", mode: 0o600 });
  }
}
