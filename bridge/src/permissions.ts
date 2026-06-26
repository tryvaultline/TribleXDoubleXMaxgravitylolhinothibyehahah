import { BridgeRole, TrustedDevice } from "./schemas.js";

export type BridgeAction =
  | "devices.read"
  | "devices.revoke"
  | "models.read"
  | "tools.read"
  | "spaces.read"
  | "tasks.read"
  | "tasks.create"
  | "tasks.message"
  | "workspace.read"
  | "workspace.write";

const permissionMatrix: Record<BridgeAction, readonly BridgeRole[]> = {
  "devices.read": ["Owner", "Admin"],
  "devices.revoke": ["Owner", "Admin"],
  "models.read": ["Owner", "Admin", "Reviewer", "Agent", "Viewer"],
  "tools.read": ["Owner", "Admin", "Reviewer", "Agent"],
  "spaces.read": ["Owner", "Admin", "Reviewer", "Agent", "Viewer"],
  "tasks.read": ["Owner", "Admin", "Reviewer", "Agent", "Viewer"],
  "tasks.create": ["Owner", "Admin", "Agent"],
  "tasks.message": ["Owner", "Admin", "Reviewer", "Agent"],
  "workspace.read": ["Owner", "Admin", "Reviewer", "Agent", "Viewer"],
  "workspace.write": ["Owner", "Admin", "Agent"]
};

export class PermissionError extends Error {
  constructor(readonly action: BridgeAction, readonly role: BridgeRole) {
    super("This trusted device is not allowed to perform that action.");
    this.name = "PermissionError";
  }
}

export function roleForDevice(device: TrustedDevice): BridgeRole {
  return device.role ?? "Owner";
}

export function canPerform(role: BridgeRole, action: BridgeAction): boolean {
  return permissionMatrix[action].includes(role);
}

export function requirePermission(device: TrustedDevice, action: BridgeAction): void {
  const role = roleForDevice(device);
  if (!canPerform(role, action)) {
    throw new PermissionError(action, role);
  }
}

export function publicPermissionMatrix(): Record<BridgeAction, readonly BridgeRole[]> {
  return permissionMatrix;
}
