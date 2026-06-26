import os from "node:os";

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

export function getLocalIp(): string {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === "IPv4" && !iface.internal && isPrivateLanIp(iface.address)) {
        return iface.address;
      }
    }
  }
  return "127.0.0.1";
}
