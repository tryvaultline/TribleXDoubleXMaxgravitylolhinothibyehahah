import os from "node:os";

export interface PrivateLanInterface {
  name: string;
  address: string;
}

export function isPrivateLanIp(ip: string): boolean {
  const parts = ip.split(".").map(Number);
  if (parts.length !== 4 || parts.some(isNaN)) return false;
  // Class A: 10.0.0.0 - 10.255.255.255
  if (parts[0] === 10) return true;
  // Class B: 172.16.0.0 - 172.31.255.255
  if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;
  // Class C: 192.168.0.0 - 192.168.255.255
  if (parts[0] === 192 && parts[1] === 168) return true;
  return false;
}

export function listPrivateLanInterfaces(): PrivateLanInterface[] {
  const interfaces = os.networkInterfaces();
  const results: PrivateLanInterface[] = [];

  for (const [name, entries] of Object.entries(interfaces)) {
    for (const iface of entries || []) {
      if (iface.family === "IPv4" && !iface.internal && isPrivateLanIp(iface.address)) {
        results.push({ name, address: iface.address });
      }
    }
  }

  return results;
}

export function getLocalIp(): string {
  return listPrivateLanInterfaces()[0]?.address ?? "127.0.0.1";
}
