# Maxgravity Bridge Contract

The mobile app treats the local Windows Maxgravity Bridge as a secure adapter over official Antigravity CLI and SDK surfaces.

## Principles

- Local-first transport only
- No undocumented database scraping
- No DOM scraping
- Desktop remains source of truth for live tasks, permissions, models, schedules, and workspace roots
- Mobile receives normalized, UI-safe payloads

## Transport

- Pairing:
  - QR code payload with bridge endpoint, device challenge, and public key material
  - Manual pairing code fallback
- Session:
  - Encrypted local WebSocket or equivalent bidirectional channel
  - Keepalive heartbeat and connection quality sampling
- Trust:
  - Trusted device registry on desktop and mobile
  - Device revoke support from either side

## API groups

### `connection`

- `pair`
- `trust`
- `disconnect`
- `health`
- `syncMetadata`

Returns:

- computer name
- online status
- connection quality
- last sync timestamp
- encryption status
- supported permission modes

### `spaces`

- `listSpaces`
- `listChats(spaceID)`
- `pinSpace`
- `renameSpace`
- `pinChat`
- `renameChat`
- `moveChat`
- `deleteLocalHistory`

### `tasks`

- `createTask`
- `continueTask`
- `steerTask`
- `fetchThreadState`

Thread payloads must include:

- visible user/assistant messages only
- safe live progress summaries
- artifacts
- approval requests
- completion summaries

### `activity`

- `runningNow`
- `needsApproval`
- `scheduled`

### `artifacts`

- `listFiles`
- `readFile`
- `listDiffs`
- `readDiff`
- `listCommands`
- `readCommandOutput`
- `listScreenshots`
- `fetchCompletionSummary`

### `workspace`

- `listApprovedRoots`
- `browse(rootID, path)`
- `chooseFolder`
- `createFolder`
- `searchMentions`

### `settings`

- `availableModels`
- `permissionModes`
- `defaultTaskBehavior`
- `notificationSupport`

Model payloads must keep these concepts separate:

- Provider: `Antigravity` or another provider only when that provider is actually configured.
- Model: the provider-owned model or route name.
- Agent Runtime: the desktop runtime that executes the work, such as `Antigravity Agent CLI`.

Antigravity routes must be labeled as Antigravity routes. The bridge must not expose them as a different provider's models.

## Roles and permissions

Trusted devices carry one bridge role:

- `Owner`
- `Admin`
- `Reviewer`
- `Agent`
- `Viewer`

The bridge is the source of truth for enforcement. The mobile app may hide unavailable controls, but every sensitive endpoint still checks the trusted-device role server-side.

## Unsupported capability policy

If Antigravity does not support a requested remote control action through official CLI or SDK surfaces, the bridge must return an explicit capability response and the app must degrade to one of:

- read-only status
- steer-only action
- desktop-required notice

The app must not invent unsupported controls.

## Implemented endpoints

- `GET /v1/connection/health`
- `POST /v1/connection/pairing-sessions`
- `GET /v1/connection/active-session`
- `POST /v1/connection/trust/register`
- `GET /v1/connection/trust/status`
- `GET /v1/connection/pending-devices` local desktop only
- `POST /v1/connection/pending-devices/:id/approve` local desktop only
- `POST /v1/connection/pending-devices/:id/reject` local desktop only
- `POST /v1/connection/trust`
- `GET /v1/connection/trusted-devices`
- `POST /v1/connection/trusted-devices/:deviceId/revoke`
- `GET /v1/capabilities`
- `GET /v1/workspace/roots`
- `GET /v1/workspace/browse`
- `GET /v1/workspace/file`
- `POST /v1/workspace/create-folder`
- `POST /v1/workspace/import-image`
- `GET /v1/spaces`
- `GET /v1/models`
- `GET /v1/tools`
- `GET /v1/plugins`
- `POST /v1/tasks`
- `POST /v1/tasks/:taskId/messages`
- `GET /v1/tasks/:taskId`
- `GET /v1/tasks/:taskId/events` as authenticated WebSocket

Workspace, task, model, tool, and trusted-device management endpoints require trusted-device credentials. Task creation requires a client idempotency key (`clientRequestId` or `X-MG-Idempotency-Key`) so repeated taps or reconnect retries do not create duplicate sensitive operations.
