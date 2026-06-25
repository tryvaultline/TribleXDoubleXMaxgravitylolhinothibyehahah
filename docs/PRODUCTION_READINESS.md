# Production Readiness Matrix

| Feature | Status | Evidence | Notes |
| --- | --- | --- | --- |
| iOS app build | Blocked | MCP reported `xcodebuild` and `xcrun` unavailable on this Windows host | GitHub Actions macOS build is configured but not verified in this local run. |
| Two-screen IA | Live | `MGRootView`, `MGSpacesView`, `MGChatThreadView` | Spaces and Chat are the primary full-screen destinations. |
| New Task contextual flow | Live | `MGFullScreenDestination.newTask` | Opens from Spaces. |
| Activity and Settings panels | Partial | `MGPanelDestination`, `MGFloatingPanelPresenter` | FloatingPanel presenter added; device interaction screenshots still blocked locally. |
| Maxgravity branding | Live | Asset catalog and app icon files | Official supplied assets are used. |
| No private Apple glass backend | Live | `MGPrivateAPIGuard`, `scripts/check-ios-static.mjs` | Local static policy check passed. |
| LiquidGlassKit | Partial | Swift package dependency and safe material wrappers | Private-backed APIs are not used. |
| Bridge health endpoint | Live | `bridge/tests/server.test.ts` | Fastify health route tested. |
| QR pairing protocol core | Live | `bridge/tests/pairing.test.ts` | Expiry, replay rejection, auth, revocation tested. |
| Desktop trust confirmation UI | Blocked | Documented in pairing protocol | Requires Windows bridge UI. |
| Workspace root confinement | Live | `bridge/tests/workspace.test.ts` | Path traversal blocked. |
| Event schema validation | Live | `bridge/tests/schemas.test.ts` | Visible task states only. |
| Official Antigravity task control | Unsupported | `docs/ANTIGRAVITY_INTEGRATION.md` | Requires verified CLI or SDK. |
| Notifications | Partial | iOS service shell | Needs device permission testing. |
| Background Live Activity updates | Blocked | `docs/LIVE_ACTIVITY_APNS_SETUP.md` | Requires APNs credentials and physical device. |
| Screenshot set | Blocked | Local plugin lacks `xcodebuild` / `xcrun` | Needs macOS simulator runtime. |

## Verification Commands

```powershell
node scripts/check-ios-static.mjs
node scripts/check-private-api.mjs
cd bridge
npm run typecheck
npm run lint
npm test
npm run build
npm run security:audit
npm run secret-scan
```
