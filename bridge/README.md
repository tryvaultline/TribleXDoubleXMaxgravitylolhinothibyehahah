# Maxgravity Bridge

The bridge is a local Windows adapter between the Maxgravity iPhone app and supported official Antigravity CLI / SDK surfaces.

It owns transport, pairing, device trust, schema validation, workspace confinement, and capability discovery. It does not scrape Antigravity desktop internals, browser DOM, private databases, or hidden state.

## Commands

```powershell
npm install
npm run typecheck
npm run lint
npm test
npm run build
npm run secret-scan
npm run dev
```

By default the bridge binds to `127.0.0.1` for development. Production LAN exposure should use a pinned certificate/public key and explicit pairing mode only.

## Status

- Pairing token expiry, replay rejection, trusted-device reconnect, revocation, workspace path confinement, event validation, and redaction are implemented and covered by tests.
- Antigravity task operations are capability-gated. When no supported machine-readable official interface is detected, methods return `Unsupported`.
- DPAPI helpers are implemented for Windows secret protection, but tests do not require storing real secrets.
