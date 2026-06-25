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

## Unsupported capability policy

If Antigravity does not support a requested remote control action through official CLI or SDK surfaces, the bridge must return an explicit capability response and the app must degrade to one of:

- read-only status
- steer-only action
- desktop-required notice

The app must not invent unsupported controls.

## Implemented endpoints

- `GET /v1/connection/health`
- `POST /v1/connection/pairing-sessions`
- `POST /v1/connection/trust`
- `GET /v1/connection/trusted-devices`
- `POST /v1/connection/trusted-devices/:deviceId/revoke`
- `GET /v1/capabilities`
- `GET /v1/workspace/roots`
- `GET /v1/workspace/browse`
- `GET /v1/tasks/:taskId/events` as authenticated WebSocket

Workspace and trusted-device management endpoints require trusted-device credentials.
