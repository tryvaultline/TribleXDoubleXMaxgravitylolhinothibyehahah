# Maxgravity Architecture

Maxgravity has two runtime parts.

```text
Maxgravity iPhone app
  -> QR pairing and trusted-device session
  -> encrypted local WebSocket / HTTPS transport
  -> Maxgravity Bridge on Windows
  -> official Antigravity CLI / SDK adapter
```

The iPhone app owns presentation, local cache, notification preferences, Keychain storage, and mobile-safe rendering. The Windows bridge owns local transport, pairing, trusted devices, workspace root policy, schema validation, redaction, and official Antigravity capability discovery.

The bridge is an adapter. It does not run a model, synthesize hidden task state, scrape the desktop app, scrape browser sessions, or read undocumented Antigravity stores.

## iOS App

- `MGRootView` owns the two-screen shell: Spaces and pushed Chat.
- New Task is contextual full-screen composition.
- Activity and Settings are panel destinations.
- `MGAppModel` centralizes mock/live capability state and route presentation.
- `MGPrivateAPIGuard` blocks accidental private Apple glass backends at compile time.

## Bridge

- `bridge/src/server.ts` exposes Fastify HTTP and WebSocket routes.
- `bridge/src/pairing.ts` owns pairing sessions, expiry, replay rejection, and trusted-device auth.
- `bridge/src/workspace.ts` confines browsing to approved roots.
- `bridge/src/antigravity-adapter.ts` keeps task control unsupported until a documented machine interface is verified.

## Capability Labels

- `Live`: implemented and verified.
- `Partial`: implemented but limited by external setup or incomplete end-to-end integration.
- `Mock`: UI-only or fixture-backed.
- `Unsupported`: not available through a supported interface.
- `Blocked`: requires external credentials, hardware, or environment.
