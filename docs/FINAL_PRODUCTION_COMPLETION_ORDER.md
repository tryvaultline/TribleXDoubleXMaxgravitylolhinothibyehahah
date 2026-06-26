# MAXGRAVITY — FINAL PRODUCTION COMPLETION ORDER

You are now the final implementation owner for Maxgravity.

Do not treat this as a prototype iteration, design exploration, or partial task. Convert the existing project into a clean, production-ready local companion app for Antigravity.

Work autonomously until all independent work is complete.

Do not stop for normal design questions, minor decisions, implementation choices, naming choices, styling choices, or non-blocking uncertainty. Make sensible technical decisions, document them, and continue.

Only pause if there is a genuine hard blocker that cannot be resolved from the current repository, installed environment, official Antigravity interfaces, or user-provided assets. Before reporting a blocker, complete every other independent item.

Do not claim a feature is live, secure, integrated, production-ready, or tested unless it has actually been implemented and verified.

---

# 1. Core Product Definition

Product name: **Maxgravity**

Maxgravity is a native iPhone companion for Antigravity sessions running on a connected Windows computer.

The Windows computer must stay online for live tasks.

Maxgravity does not run an AI model itself. It securely connects to a local desktop bridge, which adapts supported Antigravity CLI / SDK capabilities into a mobile-native experience.

Architecture:

```text
Maxgravity iPhone app
        ↓
Secure QR pairing + encrypted WebSocket
        ↓
Maxgravity Bridge on Windows
        ↓
Official Antigravity CLI / SDK
        ↓
Antigravity projects, agents, tasks, files, permissions, commands
```

The official Antigravity CLI / SDK is the authoritative source of truth.

The custom Maxgravity Bridge is an adapter only. It handles pairing, device trust, event normalization, mobile transport, local persistence, capability discovery, and secure session state. It must never become a replacement task engine or invent unsupported Antigravity behavior.

Do not scrape browser DOM, private Antigravity databases, Electron internals, undocumented APIs, CDP browser sessions, or hidden application state.

Study the existing AntigravityMobile reference only for legal, local-network transport ideas. Do not copy its interface. Do not use manual IP entry as the primary connection flow. Do not depend on CDP/browser scraping.

---

# 2. Execution Rules

Before editing:

1. Inspect the current repository, project structure, existing app, current bridge, dependencies, test state, build system, assets, and documentation.
2. Locate the uploaded Maxgravity logo and identity assets already provided in the workspace.
3. Preserve functional work where possible.
4. Create a checkpoint commit before major refactoring.
5. Create a concise architecture document before modifying integration logic.
6. Use atomic commits with clear messages.
7. Keep secrets out of the repository.
8. Never place tokens, pairing secrets, certificates, passwords, Apple credentials, or bridge keys in source control.

Decision policy:

* Do not ask for approval on UI choices already specified here.
* Do not add dependencies merely because they are popular.
* Prefer native SwiftUI and Apple frameworks first.
* Add a dependency only when it has a concrete role, a clear maintenance reason, and a tested benefit.
* Remove or avoid unused dependencies.
* Do not leave placeholders disguised as finished features.
* Clearly mark incomplete features as `Partial`, `Mock`, or `Unsupported`.

---

# 3. Required Production Architecture

## iPhone App

* Native SwiftUI.
* Minimum iOS target: iOS 17.
* Optimized first for iPhone 14 Pro Max proportions.
* Responsive on other modern iPhones.
* Use SwiftUI NavigationStack, native accessibility, Dynamic Type, VoiceOver labels, haptics, native gestures, native keyboard avoidance, and local persistence.
* No React Native.
* No Expo.
* No WebView application shell.
* No website-style responsive desktop layout.

## Windows Bridge

Use a maintainable local bridge architecture:

* TypeScript.
* Node.js runtime compatible with the existing environment.
* Fastify or similarly minimal HTTP server.
* WebSocket streaming.
* SQLite for non-sensitive local metadata if needed.
* Windows secure storage or DPAPI-backed secret protection for device trust and private local credentials.
* Versioned API protocol.
* Strict schema validation for every request and event.
* Structured logging with redaction.
* Safe local startup and shutdown scripts.
* Local-network-only by default.
* No cloud relay.
* No port forwarding.
* No public internet listener by default.

## Integration Layer

Create a dedicated Antigravity adapter interface:

```text
AntigravityAdapter
- getCapabilities()
- listSpaces()
- listChats(spaceId)
- createTask()
- sendMessage()
- streamTaskEvents()
- listWorkspaceRoots()
- browseWorkspace()
- createFolder()
- getPermissionModes()
- requestApproval()
- resolveApproval()
- listFiles()
- readFile()
- getDiff()
- listCommands()
- getCommandOutput()
- getTaskSummary()
- getSchedule()
- createSchedule()
```

Use official Antigravity CLI / SDK paths where available.

If a feature cannot be supported officially:

* Do not fake it.
* Do not scrape it.
* Implement the supported fallback.
* Mark the capability accurately.
* Ensure Maxgravity remains useful for tasks launched through Maxgravity itself.

---

# 4. Information Architecture — Only Two Main Screens

Maxgravity must not become a dashboard with many permanent tabs.

There are only two main full-screen destinations:

1. **Spaces**
2. **Chat**

New Task is contextual and opens from Spaces.

Activity and Settings are not full standalone primary pages. They open as swipeable Liquid Glass panels.

Connection setup is a first-launch flow only, not a permanent root destination.

Files, diffs, commands, approvals, schedules, and code viewers are contextual drill-ins or sheets.

No persistent three-tab dashboard.
No generic bottom navigation.
No sidebar.
No desktop-style multi-column layout.

---

# 5. Brand and Visual System

The app name is **Maxgravity**.

Do not use Antigravity as the primary visual brand.

Use the supplied Maxgravity logo and identity assets in:

* App icon treatment
* Launch state
* Spaces header
* Connection state
* Empty states
* Loading state
* Agent activity state
* Completion state
* QR pairing confirmation

Do not create substitute generic logos.
Do not use letter placeholders.
Do not use avatar circles.

## Color Rules

The app must closely follow a premium ChatGPT-like dark visual discipline:

* Main background: true black
* Surface background: deep graphite
* Primary text: off-white
* Secondary text: muted gray
* Tertiary text: subdued graphite gray
* Borders: subtle translucent white
* Icons: white or gray based on hierarchy
* No blue product accent anywhere

Use color only for semantic information:

* Green: success, online, additions, passing checks
* Red: deletion, error, destructive action
* Amber: warning, approval required, waiting state
* Maxgravity gradient: logo, rare primary moments, micro-highlights only

Never create colorful dashboard cards.
Never use random gradients in backgrounds.
Never use neon edges around all components.

## Typography

Use:

* SF Pro for interface text
* SF Mono for code, paths, commands, terminal output, IDs, and technical metadata

Typography must feel native to iPhone, not like a desktop dashboard.

Use Dynamic Type styles and preserve readability:

* Main screen title: native large title scale only where needed
* Section title: native title or headline scale
* Main row text: approximately iOS 17pt body scale
* Secondary metadata: approximately 13–15pt
* Code: monospaced, compact but readable
* Do not use oversized dashboard headers
* Do not split a page into a giant title region and an unrelated lower content region

---

# 6. Glass System and Visual Quality

Use Liquid Glass heavily for interactive controls and floating surfaces.

Required dependency:

`DnV1eX/LiquidGlassKit`

Safety requirements:

* Audit the dependency before integration.
* Use only its App Store-safe public API path.
* Do not use private UIKit classes.
* Do not use `_UILiquidLensView`.
* Do not use `NSClassFromString` for private Apple classes.
* Do not use `CABackdropLayer` private-only behavior in the shipping configuration.
* Ensure the production target compiles without private-symbol paths.
* Add a build-time safeguard that prevents private API code paths from being enabled accidentally.

Create a unified glass component system:

```text
MGGlassSurface
MGGlassButton
MGGlassIconButton
MGGlassComposer
MGGlassPanel
MGGlassPill
MGGlassListGroup
MGGlassAttachmentMenu
MGGlassCompletionEmbed
```

Use native iOS 26 Liquid Glass APIs when available.

On iOS 17–25, use the safe LiquidGlassKit fallback only.

Apply glass to:

* Header controls
* Connection pill
* Expand/collapse controls
* Space groups
* New Task button
* Composer
* Composer accessory controls
* Attachment menu
* Model selector
* Activity panel
* Settings panel
* Context menus
* Approval panel
* Completion embed
* Floating controls
* Selected interactive states

Keep long-form text, code, terminal output, and diffs readable through darker opaque or semi-opaque content layers.

Glass must look physical and refined, not overexposed or blurry.

---

# 7. Interaction, Physics, Haptics, and Animation

The app must feel physically responsive and smooth.

Implement:

* Button touch-down compression
* Soft spring-back behavior
* Slight depth shift on press
* Haptic feedback for primary actions
* Selection haptics for controls
* Success haptic for completion
* Warning haptic for approval requests
* Subtle drag resistance in panels
* Natural swipe dismissal
* Smooth expand/collapse animation for Spaces
* Chevron rotation with spring response
* Native interactive swipe-back behavior
* Smooth keyboard interaction
* Streaming text animation
* Natural type-on response behavior
* Gentle deletion / replacement animation for live agent text
* Tiny shimmer on active labels such as Planning, Writing, Running, and Syncing
* Quiet three-dot animation for active work
* No loud glitter
* No gaming-style animations
* No constant looping motion
* Respect Reduce Motion
* Respect Reduce Transparency

Use native SwiftUI animation systems first:

* `matchedGeometryEffect`
* `symbolEffect`
* `PhaseAnimator`
* `KeyframeAnimator`
* `sensoryFeedback`
* SwiftUI spring animations
* native transition APIs

Use `FloatingPanel` for swipeable glass panels and advanced drag physics.

Do not add FluidTabBarController.
Do not add SideMenu.
Do not add PanModal.
Do not add SkyFloatingLabelTextField.
Do not add SwiftUI-Neumorphic.
Do not add Hero unless native matched transitions cannot achieve a specific verified required interaction.
Do not add Texture unless profiling proves a real scrolling or rendering bottleneck.
Do not add Lottie except for a small number of high-value states such as pairing success or task completion.

---

# 8. First Launch and Connection Flow

When no computer is paired, show a dedicated connection flow.

Layout:

* Maxgravity logo
* Maxgravity name
* One clean message:
  “Connect your computer to continue”
* Primary action:
  “Scan QR code”
* Secondary action:
  “Enter pairing code”
* Small note:
  “Your computer must stay online for live tasks.”

No generic account signup.
No social login.
No cloud profile system.

## QR Pairing

Implement real QR pairing between the iPhone app and Windows bridge.

Desktop bridge must create:

* Short-lived pairing session
* Temporary one-time token
* Expiry timestamp
* Local connection address
* Public-key or certificate fingerprint
* Bridge version
* Device trust confirmation request

QR flow:

1. Desktop bridge starts pairing mode.
2. Desktop displays QR code.
3. iPhone scans QR code.
4. iPhone validates expiry and bridge fingerprint.
5. Desktop confirms new device trust.
6. Secure device identity is stored.
7. Future reconnections happen automatically.

Security requirements:

* Local-network-only by default
* Secure WebSocket transport
* Certificate or public-key pinning
* Expiring pairing token
* Replay protection
* Device revocation
* Trusted-device list
* Explicit disconnect
* iOS Keychain for mobile secrets
* Windows protected storage for bridge secrets
* No plaintext durable pairing token
* No silent connection to unknown bridges
* No arbitrary LAN scanning

After pairing, show:

* Connected computer name
* Online state
* Last sync
* Connection quality
* Bridge version
* Disconnect this computer action

Use “Disconnect this computer”, never “Log out”.

---

# 9. Spaces Screen

Spaces is the home screen after successful connection.

## Header

Include:

* Maxgravity logo
* Maxgravity name
* Compact connected-computer pill
* Activity icon
* Settings icon

Every actionable icon must have an accessibility label and a meaningful purpose.

## Connection Pill

Tapping the connection pill opens a small Liquid Glass panel with:

* Computer name
* Online/offline state
* Last sync
* Connection quality
* Link another computer
* Disconnect this computer

## Spaces Content

Title:

`Your Spaces`

Each Space is a refined expandable Liquid Glass group.

Each Space contains:

* Space icon
* Space name
* Number of chats
* Expand/collapse control
* Optional subtle running or warning state

When expanded, chats appear as nested rows under that Space.

Each chat row includes:

* Chat icon
* Chat title
* Recent timestamp
* Optional running state
* Optional pinned indicator
* Disclosure affordance

Do not make every chat a large heavy card.

Example:

```text
Antigravity App
  Implement bottom bar
  Fix auth flow bug
  Improve onboarding
  Add dark mode
```

Long press Space actions:

* Pin
* Rename
* Collapse all
* Manage workspace root

Long press Chat actions:

* Pin
* Rename
* Move to Space
* Delete local history

At the bottom of the screen, show a large soft rounded Maxgravity primary action:

`New task`

The button should feel physical, premium, and calm.

---

# 10. New Task Flow

New Task opens from Spaces as a focused full-screen composition flow.

It is not a permanent dashboard page.

## Header

* Native back control
* Selected Space name
* Compact connection state
* No crowded toolbar

## Main Composer

Use a large deep graphite squircle composer.

Placeholder:

`Describe what you want Maxgravity to build, change, review, or investigate…`

The composer must be the main focus of the screen.

Inside or attached to the composer include:

* Plus button
* Slash command button
* @ workspace mention button
* Model selector
* Microphone button
* Send button

The model selector must sit beside the microphone and send control.

## Model Picker

Open a compact Liquid Glass sheet listing models exposed by the connected Antigravity environment.

Examples may include:

* Auto
* GPT-4o
* GPT-4.1
* GPT-5 Codex
* GPT-5 Codex High

Do not hard-code availability in production.
Use bridge capabilities and availability data.

## Plus Attachment Menu

The uploaded ChatGPT attachment-menu screenshot is the primary visual reference.

Recreate the interaction nearly exactly:

* Large dark translucent floating Liquid Glass panel
* Rich graphite material
* Deep blur
* Soft refraction
* Large circular dark icon wells
* Large native-scale labels
* Generous vertical spacing
* Panel floating over the conversation or composer
* Background dim and blur behind it
* Spring-based entrance
* Natural drag dismissal
* Tap-outside dismissal
* Soft haptic feedback
* No tiny settings-list appearance
* No dashboard menu

Primary actions in exact order:

1. Camera
2. Photos
3. Files
4. Plugins

Below that, use an expandable secondary tools section for:

* Mention workspace file
* Plan mode
* Choose working folder
* Create folder
* Permissions

## Remote Folder Picker

Folder browsing must be secure and bridge-controlled.

Requirements:

* Only approved workspace roots are visible
* Browse folders
* Select folder
* Create folder
* Confirm selection
* No unrestricted desktop filesystem exposure
* No user-visible fake local mobile file picker pretending to access Windows files

## Permissions

Expose only permission modes that the desktop bridge can enforce:

* Sandbox
* Ask when needed
* Sensitive auto-review
* Full access

Never show a selected mode that is not actually enforced by the desktop adapter.

---

# 11. Chat Screen

Chat is the second main destination.

## Header

Include:

* Back button to Spaces
* Chat title
* Compact running / connection state
* Overflow menu

Overflow actions:

* Pin chat
* Rename chat
* View files
* View commands
* View activity
* Delete local chat history

## User Messages

User messages must be:

* Embedded graphite bubbles
* Right aligned
* Soft corners
* Compact
* Readable
* Timestamped
* Support file / media embeds
* Avoid excessive decoration

## Maxgravity Agent Messages

Agent responses must not look like generic giant assistant cards.

They must flow naturally in the thread:

* Small Maxgravity label
* No avatar
* Clear response text
* Integrated live work state below when active
* Contextual artifacts inside the flow
* Good spacing
* No repetitive heavy borders

Never expose hidden chain-of-thought.

Show safe operational summaries only:

* Planning changes
* Reading files
* Checking workspace
* Updating styles
* Applying changes
* Running commands
* Running tests
* Awaiting approval
* Task completed

## Live Agent Activity

Show a compact expandable timeline:

```text
Planning changes
Reading BottomBar.tsx
Updating styles
Applying changes
Running checks
Awaiting approval
```

Each entry can include:

* Semantic icon
* Title
* One-line detail
* Duration
* Current active animation
* Completion check

Keep the collapsed state concise.

## In-Thread Artifacts

Implement interactive embedded artifacts for:

* Files
* Links
* File diff summaries
* Command results
* Screenshots
* Approval requests
* Test outcomes
* Schedules

Examples:

```text
BottomBar.tsx  +48  -23
README.md
npm test
Visual check passed
Approval required: install dependency
```

---

# 12. Contextual Task Detail

Opening an artifact must lead to a clean contextual task-detail screen or sheet.

Use no more than three segmented sections:

* Files
* Changes
* Commands

## Files

* Single-column tree
* Folder/file icons
* Search
* Read-only by default
* File selection opens code viewer

## Code Viewer

* SF Mono
* Syntax highlighting
* Read-only by default
* Copy action
* Search in file
* Semantic green additions
* Semantic red deletions
* Amber modified lines only where needed
* Good line spacing and iPhone-readable horizontal behavior

## Changes

* Changed-file list
* Addition/deletion counts
* Full diff viewer
* Clear status
* No rainbow syntax overload

## Commands

* Chronological command list
* Command text
* Result
* Runtime
* Expandable output
* Copy output
* Clear success/failure state

---

# 13. Approvals, Steering, Completion

## Approval Panel

Approval requests must clearly state:

* What action is requested
* Why approval is required
* Affected files or command
* Risk level
* Approve
* Reject
* Steer

Steer opens a compact input:

`Tell Maxgravity what to change before continuing…`

## Completion Embed

At task completion, show a premium completion embed containing:

* Green semantic success state
* Concise final summary
* Files modified
* Lines added
* Lines removed
* Tests/checks run
* Remaining warnings
* Copy reply button

Copy Reply must copy the complete final Maxgravity response.

Do not only copy the short summary.

---

# 14. Activity and Settings Panels

Activity and Settings must be swipeable FloatingPanel panels.

They are not permanent root pages and not bottom-tab items.

## Activity Panel

Open from Spaces header.

Show only:

* Running now
* Needs approval
* Scheduled

No analytics dashboard.
No charts unless they directly communicate a live system problem.

## Settings Panel

Open from the Spaces header.

Use grouped native settings rows with icons.

Sections:

### Connection

* Connected computer
* Connection health
* Last sync
* Link another computer
* Disconnect this computer

### Notifications

* Task completed
* Approval required
* Connection lost
* Scheduled task reminder

### Live Activity

* Enable / disable
* Active task display
* Update frequency diagnostic
* Permission state

### Default Task Behavior

* Default model
* Default permission mode
* Default Plan mode
* Default Space

### Appearance

* System
* Dark
* High contrast
* Glass intensity
* Reduce motion support
* Reduce transparency support

### Privacy

* Local cache
* Clear local history
* Trusted devices
* Encryption state

---

# 15. Notifications and Live Activity

Implement notification architecture now.

## Local Notifications

Support:

* Task completed
* Approval required
* Connection lost
* Scheduled task ready

Use correct permission prompts and settings fallback.

## Live Activity

Add an ActivityKit extension.

Display:

* Active task title
* Current stage
* Connected computer name
* Compact task status
* Approval-required state
* Minimal progress state

Support:

* Start
* Update
* End
* Recovery after reconnect where possible

Implement local in-app update behavior first.

Create a production-ready APNs adapter module for remote updates.

Do not claim remote background Live Activity updates are operational unless valid Apple signing, entitlements, APNs configuration, push tokens, and actual device testing are complete.

Document exactly what secrets and Apple Developer configuration remain external.

---

# 16. Quality, Performance, and Accessibility

The finished app must not feel like a basic prototype.

Required quality work:

* Audit all text sizes
* Audit all icon sizes
* Audit all spacing
* Audit safe areas
* Audit keyboard behavior
* Audit dark-mode contrast
* Audit Dynamic Type
* Audit VoiceOver labels
* Audit Reduce Motion
* Audit Reduce Transparency
* Audit loading states
* Audit offline state
* Audit reconnection state
* Audit empty Spaces state
* Audit no-results state
* Audit permission-denied state
* Audit bridge-unavailable state
* Audit task-failed state
* Audit long chat performance
* Audit large terminal output
* Audit large diff rendering
* Audit scrolling FPS
* Audit memory behavior
* Audit image upload behavior
* Audit destructive actions
* Audit network loss during active task

Use native skeleton/redaction loading states where appropriate.

Do not show generic spinners everywhere.

Use shimmer only where it helps perceived loading quality.

---

# 17. Testing and Delivery

Implement and run:

## Bridge Tests

* Pairing token expiry
* Pairing token replay rejection
* Unknown-device rejection
* Trusted-device reconnect
* Device revocation
* WebSocket authentication
* Permission capability enforcement
* Folder-root confinement
* Path traversal protection
* Event schema validation
* Sensitive log redaction
* Connection loss
* Reconnect behavior

## App Tests

* Spaces expand/collapse
* Open chat
* New Task creation
* Model selector
* Attachment menu
* Folder picker
* Permission picker
* Streaming state rendering
* Approval flow
* Copy Reply
* Settings panel
* Activity panel
* Offline state
* Notification permission state
* Live Activity state where testable

## CI

Create GitHub Actions for:

* Swift formatting or linting
* Swift build
* Unit tests
* Bridge linting
* Bridge type checking
* Bridge tests
* Security audit
* Dependency license review
* Secret scanning
* Release artifact preparation

Prepare signing documentation and a release workflow, but do not store Apple signing material in the repository.

## Documentation

Create:

* `README.md`
* `docs/ARCHITECTURE.md`
* `docs/LOCAL_BRIDGE_SECURITY.md`
* `docs/PAIRING_PROTOCOL.md`
* `docs/ANTIGRAVITY_INTEGRATION.md`
* `docs/IOS_BUILD_AND_SIGNING.md`
* `docs/LIVE_ACTIVITY_APNS_SETUP.md`
* `docs/PRODUCTION_READINESS.md`
* `docs/KNOWN_LIMITATIONS.md`

---

# 18. Final Completion Gate

Do not report completion until all independent work is completed.

Before the final report:

1. Build the bridge.
2. Build the iOS app or prepare a verified CI build where local Xcode is unavailable.
3. Run all tests.
4. Run static checks.
5. Verify no secrets are committed.
6. Verify no private Apple API path is enabled.
7. Verify no blue product accent exists.
8. Verify the application is branded Maxgravity everywhere.
9. Verify there are only two primary full-screen destinations: Spaces and Chat.
10. Verify New Task is contextual.
11. Verify Activity and Settings are floating panels.
12. Verify the ChatGPT-style attachment menu is implemented.
13. Verify all actionable rows have meaningful icons.
14. Verify all interaction surfaces use the unified glass system.
15. Verify haptics and motion are implemented.
16. Verify the QR pairing flow is genuinely implemented or accurately marked partial.
17. Verify official Antigravity integration status is explicitly documented.
18. Verify notification and Live Activity status is explicitly documented.
19. Capture polished screenshots for:

    * Connection flow
    * Spaces
    * New Task
    * Attachment menu
    * Chat during live work
    * Diff / commands
    * Approval state
    * Completion state
    * Activity panel
    * Settings panel
20. Write a final verification report.

The final report must contain a strict matrix:

```text
Feature | Status | Evidence | Notes
Live | Fully working and verified
Partial | Implemented but limited
Mock | UI-only and clearly isolated
Unsupported | Not available through supported Antigravity interfaces
Blocked | Requires external credentials or environment
```

Do not use vague wording such as “mostly done”, “should work”, “probably”, or “production ready” without evidence.

Continue until this product is clean, stable, coherent, testable, branded, and honestly documented.
