# Maxgravity

Maxgravity is a native SwiftUI iPhone companion app for Antigravity sessions running on a connected Windows machine.

This workspace contains:

- A native iPhone-only SwiftUI app targeting iOS 17+
- A local TypeScript Maxgravity Bridge scaffold for Windows
- QR pairing, trusted-device, workspace confinement, and bridge event schemas
- CI for iOS builds, bridge checks, security audit, and static policy checks

## Structure

- `Maxgravity/`: app source, assets, and plist
- `Maxgravity.xcodeproj/`: Xcode project
- `bridge/`: local bridge source, tests, and package scripts
- `docs/`: production architecture, security, pairing, integration, build, and readiness documents
- `scripts/check-ios-static.mjs`: private API and product-accent policy check

## Current implementation status

- Implemented:
  - Two-main-screen iOS shell: Spaces and Chat
  - Contextual New Task flow and attachment menu
  - Activity and Settings panel presentation state
  - Real Maxgravity brand assets and app icons
  - Bridge pairing token expiry, replay rejection, trusted-device auth, revocation, workspace root confinement, schema validation, redaction, and tests
  - CI artifact packaging for unsigned iOS builds
- Partial:
  - FloatingPanel-backed Activity and Settings panels
  - ActivityKit/local notification shell
  - Bridge-to-iOS live event contract
- Unsupported until verified:
  - Official Antigravity task/session control through CLI or SDK
  - Remote background Live Activity pushes from Windows bridge without Apple Developer/APNs setup

## Open in Xcode

1. Open `Maxgravity.xcodeproj` on macOS with Xcode that supports iOS 17+.
2. Run the `Maxgravity` scheme on an iPhone 14 Pro Max simulator first.
3. Validate smaller iPhone layouts, Dynamic Type, Reduce Motion, and Reduce Transparency.
4. Use GitHub Actions artifacts for unsigned IPA packaging when local signing is unavailable.

## Bridge commands

```powershell
cd bridge
npm install
npm run typecheck
npm run lint
npm test
npm run build
npm run secret-scan
```
