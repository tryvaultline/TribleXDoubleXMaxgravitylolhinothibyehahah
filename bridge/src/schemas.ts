import { z } from "zod";

export const CapabilityStateSchema = z.enum(["Live", "Partial", "Mock", "Unsupported"]);

export const BridgeCapabilitySchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  status: CapabilityStateSchema,
  notes: z.string().min(1)
});

export const PairingSessionSchema = z.object({
  sessionId: z.string().min(16),
  address: z.string().url(),
  token: z.string().min(24),
  expiresAt: z.string().datetime(),
  bridgeFingerprint: z.string().min(8),
  bridgeVersion: z.string().min(1)
});

export const TrustDeviceRequestSchema = z.object({
  sessionId: z.string().min(16),
  token: z.string().min(24),
  deviceName: z.string().min(1).max(80),
  devicePublicKeyFingerprint: z.string().min(8).max(128),
  platform: z.string().max(40).optional()
});

export const TrustedDeviceSchema = z.object({
  id: z.string().min(16),
  name: z.string().min(1),
  publicKeyFingerprint: z.string().min(8),
  pairedAt: z.string().datetime(),
  revokedAt: z.string().datetime().optional(),
  secretHash: z.string().min(64)
});

export const BridgeEventSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("task.stage"),
    taskId: z.string().min(1),
    stage: z.enum([
      "Planning changes",
      "Reading files",
      "Checking workspace",
      "Updating styles",
      "Applying changes",
      "Running commands",
      "Running tests",
      "Awaiting approval",
      "Task completed",
      "Task failed"
    ]),
    detail: z.string().max(300),
    emittedAt: z.string().datetime()
  }),
  z.object({
    type: z.literal("approval.required"),
    taskId: z.string().min(1),
    approvalId: z.string().min(1),
    action: z.string().min(1),
    reason: z.string().min(1),
    affectedItems: z.array(z.string()).max(30),
    emittedAt: z.string().datetime()
  }),
  z.object({
    type: z.literal("command.output"),
    taskId: z.string().min(1),
    commandId: z.string().min(1),
    chunk: z.string().max(12_000),
    emittedAt: z.string().datetime()
  })
]);

export const WorkspaceRootSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  path: z.string().min(1)
});

export type CapabilityState = z.infer<typeof CapabilityStateSchema>;
export type BridgeCapability = z.infer<typeof BridgeCapabilitySchema>;
export type PairingSessionPayload = z.infer<typeof PairingSessionSchema>;
export type TrustDeviceRequest = z.infer<typeof TrustDeviceRequestSchema>;
export type TrustedDevice = z.infer<typeof TrustedDeviceSchema>;
export type BridgeEvent = z.infer<typeof BridgeEventSchema>;
export type WorkspaceRoot = z.infer<typeof WorkspaceRootSchema>;
