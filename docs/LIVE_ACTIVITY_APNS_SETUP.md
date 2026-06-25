# Live Activity And APNs Setup

The app contains a local ActivityKit controller for foreground start/update/end behavior. True background updates from the Windows bridge require Apple push infrastructure and cannot be claimed live until device-tested.

Required external Apple setup:

- Apple Developer team.
- App ID with Push Notifications.
- ActivityKit entitlement.
- APNs auth key.
- Push token registration on the iPhone.
- Secure token exchange from iPhone to bridge.
- Bridge APNs provider module.
- Physical-device test, not simulator-only validation.

Current status:

- Local in-app Live Activity state: `Partial`.
- Background bridge-driven updates: `Blocked`.
- APNs provider credentials: `Blocked`.
