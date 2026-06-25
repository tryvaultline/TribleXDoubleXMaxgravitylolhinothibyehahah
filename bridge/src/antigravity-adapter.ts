import { BridgeCapability } from "./schemas.js";

export interface AntigravityAdapter {
  getCapabilities(): Promise<BridgeCapability[]>;
}

export class UnsupportedCapabilityError extends Error {
  constructor(capability: string) {
    super(`${capability} is not available through a verified official Antigravity CLI or SDK contract yet.`);
    this.name = "UnsupportedCapabilityError";
  }
}

export class OfficialAntigravityAdapterPlaceholder implements AntigravityAdapter {
  async getCapabilities(): Promise<BridgeCapability[]> {
    return [
      {
        id: "antigravity.official-interface",
        title: "Official Antigravity CLI / SDK",
        status: "Unsupported",
        notes: "No documented machine-readable task-control contract is verified in this repository."
      },
      {
        id: "tasks.create",
        title: "Create Antigravity task",
        status: "Unsupported",
        notes: "Task launch remains disabled until an official local CLI or SDK transport is validated."
      },
      {
        id: "tasks.live-events",
        title: "Live Antigravity task events",
        status: "Unsupported",
        notes: "The bridge exposes authenticated WebSocket transport, but real Antigravity event streaming is not connected."
      },
      {
        id: "approvals.resolve",
        title: "Resolve approval requests",
        status: "Unsupported",
        notes: "Approval control requires a supported desktop-side Antigravity interface."
      }
    ];
  }
}
