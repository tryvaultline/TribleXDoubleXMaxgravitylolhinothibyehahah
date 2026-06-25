# Maxgravity

Maxgravity is a native SwiftUI iPhone companion app for Antigravity sessions running on a connected Windows machine.

This workspace contains:

- A new iOS app scaffold targeting iOS 17+
- Phase 1 and 2 native UI implementation with realistic mock data
- Bridge-facing protocols and DTOs for the local Maxgravity Bridge
- Preview-friendly architecture for macOS/Xcode handoff

## Structure

- `Maxgravity/`: app source, assets, and plist
- `Maxgravity.xcodeproj/`: Xcode project
- `docs/bridge-contract.md`: local bridge API contract and payload guidance

## Current implementation status

- Implemented:
  - First launch pairing shell
  - Spaces
  - New Task
  - Chat / Live Task Thread
  - Task detail drill-ins
  - Activity
  - Schedule sheet
  - Settings
  - Shared UI system and mock repositories
- Deferred to a macOS/Xcode environment:
  - Build verification
  - Real iOS 26 Liquid Glass API adoption against the iOS 26 SDK
  - Screenshot capture
  - Final logo/app-icon asset integration
  - Real Maxgravity Bridge transport

## Open in Xcode

1. Open `Maxgravity.xcodeproj` on macOS with Xcode that supports iOS 17+.
2. Replace the placeholder logo/icon treatment with the official Maxgravity assets.
3. If building with the iOS 26 SDK, swap the isolated surface wrappers to the official Liquid Glass APIs noted in code comments.
4. Run on iPhone 14 Pro Max first, then validate smaller iPhones.
