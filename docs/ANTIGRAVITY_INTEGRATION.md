# Antigravity Integration

Maxgravity must use official Antigravity CLI or SDK surfaces. It must not scrape DOM, Electron internals, private app databases, CDP sessions, or hidden state.

## Current Status

`bridge/src/antigravity-adapter.ts` includes the adapter boundary and keeps every Antigravity task method unsupported until an official machine-readable interface is verified.

Task control is currently `Unsupported` because this repository does not include a documented machine-readable Antigravity CLI or SDK contract.

Public references checked on 2026-06-25:

- https://antigravity.google/docs/cli-overview
- https://antigravity.google/docs/sdk-overview
- https://github.com/google-antigravity/antigravity-cli

## Required Verification

Before enabling live task control, verify official support for:

- Capability discovery.
- Listing spaces and chats.
- Creating tasks.
- Sending follow-up messages.
- Streaming visible task events.
- Reading files through approved roots.
- Reading diffs and command output.
- Resolving approval requests.
- Scheduling tasks.

If any item is unsupported, Maxgravity must show a read-only, steer-only, or desktop-required state rather than inventing behavior.
