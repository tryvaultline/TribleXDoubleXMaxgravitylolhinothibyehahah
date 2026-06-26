import { z } from "zod";

export const CapabilityStateSchema = z.enum(["Live", "Partial", "Mock", "Unsupported"]);
export const BridgeRoleSchema = z.enum(["Owner", "Admin", "Reviewer", "Agent", "Viewer"]);

export const IdempotencyKeySchema = z
  .string()
  .min(8)
  .max(128)
  .regex(/^[A-Za-z0-9._:-]+$/);

export const BridgeCapabilitySchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  status: CapabilityStateSchema,
  notes: z.string().min(1)
});

export const PairingSessionSchema = z.object({
  sessionId: z.string().min(16),
  address: z.string().url(),
  token: z.string().min(24).optional(),
  protocolVersion: z.string().min(1).optional(),
  httpsHost: z.string().min(1).optional(),
  httpsPort: z.number().int().positive().optional(),
  wssPort: z.number().int().positive().optional(),
  expiresAt: z.string().datetime(),
  bridgeFingerprint: z.string().min(8),
  bridgeVersion: z.string().min(1)
});

export const TrustDeviceRequestSchema = z.object({
  sessionId: z.string().min(16),
  token: z.string().min(8).max(64).optional(),
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
  role: BridgeRoleSchema.default("Owner"),
  secretHash: z.string().min(64)
});

export const ModelProviderSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1)
});

export const ModelIdentitySchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1)
});

export const AgentRuntimeSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  status: CapabilityStateSchema
});

export const ModelDescriptorSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  description: z.string().min(1),
  provider: ModelProviderSchema,
  model: ModelIdentitySchema,
  agentRuntime: AgentRuntimeSchema,
  speed: z.string().min(1),
  effort: z.string().min(1),
  capabilities: z.array(z.string().min(1)).max(12),
  isRecommended: z.boolean(),
  state: z.enum(["live", "partial", "mock", "unsupported"])
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

export const WorkspaceBrowseQuerySchema = z.object({
  rootId: z.string().min(1),
  path: z.string().min(1).default(".")
});

export const WorkspaceFileQuerySchema = z.object({
  rootId: z.string().min(1),
  path: z.string().min(1)
});

export const WorkspaceCreateFolderRequestSchema = z.object({
  rootId: z.string().min(1),
  path: z.string().min(1).default("."),
  name: z.string().min(1).max(120)
});

export const WorkspaceImportImageRequestSchema = z.object({
  rootId: z.string().min(1),
  path: z.string().min(1).default("."),
  fileName: z.string().min(1).max(180),
  base64Data: z.string().min(4).max(14_000_000)
});

export const CreateTaskRequestSchema = z.object({
  spaceId: z.string().min(1).max(160),
  title: z.string().trim().min(1).max(180).optional(),
  prompt: z.string().trim().min(1).max(30_000),
  workspaceRoot: z.string().min(1).max(1_000),
  selectedModelId: z.string().min(1).max(128).optional(),
  clientRequestId: IdempotencyKeySchema.optional()
});

export const SendTaskMessageRequestSchema = z.object({
  prompt: z.string().trim().min(1).max(30_000),
  workspaceRoot: z.string().min(1).max(1_000),
  clientRequestId: IdempotencyKeySchema.optional()
});

export const TaskIdParamsSchema = z.object({
  taskId: z.string().min(1).max(160)
});

export type CapabilityState = z.infer<typeof CapabilityStateSchema>;
export type BridgeRole = z.infer<typeof BridgeRoleSchema>;
export type BridgeCapability = z.infer<typeof BridgeCapabilitySchema>;
export type ModelDescriptor = z.infer<typeof ModelDescriptorSchema>;
export type PairingSessionPayload = z.infer<typeof PairingSessionSchema>;
export type TrustDeviceRequest = z.infer<typeof TrustDeviceRequestSchema>;
export type TrustedDevice = z.infer<typeof TrustedDeviceSchema>;
export type BridgeEvent = z.infer<typeof BridgeEventSchema>;
export type WorkspaceRoot = z.infer<typeof WorkspaceRootSchema>;
