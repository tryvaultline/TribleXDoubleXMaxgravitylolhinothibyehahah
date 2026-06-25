# Local Bridge Security

The bridge is local-network only by default. Development startup binds to `127.0.0.1`. LAN exposure must be explicit and paired with certificate or public-key pinning.

## Implemented

- Expiring one-time pairing token.
- Replay rejection after successful trust.
- Trusted-device registry.
- Device revocation.
- Authenticated workspace routes.
- Workspace path traversal protection.
- Zod schema validation.
- Structured log redaction.
- Secret scan in CI.
- Windows DPAPI helper module for current-user secret protection.

## Required Before LAN Production

- Generate local certificate or public-key material on first bridge launch.
- Pin the bridge fingerprint in the iOS Keychain after QR pairing.
- Store device secrets with Windows protected storage, not plaintext JSON.
- Require desktop-side trust confirmation before completing pairing.
- Bind LAN listener only during explicit pairing or trusted reconnect mode.

No pairing token, device secret, private key, Apple credential, APNs key, or signing material belongs in the repository.
