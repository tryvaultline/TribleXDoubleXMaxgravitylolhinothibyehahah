# Pairing Protocol

The bridge creates a short-lived session and displays it as a QR code.

Payload fields:

- `sessionId`
- `address`
- `token`
- `expiresAt`
- `bridgeFingerprint`
- `bridgeVersion`

Flow:

1. Desktop bridge creates a pairing session.
2. iPhone scans the QR payload.
3. iPhone validates expiry and displays the bridge fingerprint.
4. Desktop confirms the new device.
5. Bridge consumes the token once and stores a trusted-device record.
6. Bridge returns a one-time device secret to the iPhone over the secure channel.
7. Future requests use trusted-device credentials and pinned bridge identity.

Implemented in `bridge/src/pairing.ts`:

- Token expiry.
- Token replay rejection.
- Unknown-device rejection.
- Invalid-secret rejection.
- Device revocation rejection.

Still external:

- Camera scanner UI on device.
- Desktop confirmation UI.
- Certificate/public-key generation and pin persistence.
- iOS Keychain persistence.
