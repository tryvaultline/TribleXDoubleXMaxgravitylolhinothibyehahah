# Maxgravity Release Notes (v1.0)

Welcome to the **Maxgravity v1.0** production release. Maxgravity is a premium SwiftUI-native iOS companion application for Google Antigravity running on your connected Windows PC. 

This release provides a SideStore-compatible, App Store-safe unsigned IPA package ready for physical iPhone installation.

---

## What's New in v1.0

### 1. Unified Glass System (Liquid Glass)
* Implemented a premium ChatGPT-style dark visual discipline utilizing `LiquidGlassKit` via App Store-safe public APIs.
* Pure black main backgrounds combined with deep graphite card containers and subtle, high-contrast typography.
* Applied rich glass surfaces to header controls, connection pills, composer bars, popups, and contextual widgets.

### 2. Streamlined Navigation Architecture
* Replaced the three-tab desktop-style dashboard with an iPhone-first navigation layout.
* **Only Two Main Full-Screen Destinations**:
  1. **Spaces Screen**: Home dashboard showing paired desktop health and expandable/collapsible space lists with nested chats.
  2. **Chat Screen**: Clean thread displaying user prompts and streaming agent output.
* **Swipeable Floating Panels**: Settings and Activity actions slide up from the bottom as floating overlay panels.
* **Contextual Modals**: New Task, folder browsing, model pickers, and code diff summaries open contextually to prevent screen navigation fatigue.

### 3. ChatGPT-Style Composer & Attachment Panel
* Native squircle composer with quick actions for slash commands, file mentions, permission scopes, and model options.
* **Liquid Glass Attachment Menu**: Custom overlay that replicates the ChatGPT design language, featuring large circular graphite icon wells, native-scale text, and spring dismissals.
* Attachment capabilities include Camera, Photos, Files, and Plugins.

### 4. Live Agent Execution & Visual QA
* Live task status displays safe user-facing stages (Planning, Reading files, Compiling, Testing, Awaiting approval).
* Direct in-thread embeds for file diff highlights, command outcomes, test summaries, and completion metadata.
* Integrated "Copy Reply" widget that copies the entire final response with one tap.

### 5. Local Secure Pairing & Bridge Protocol
* Setup QR-code pairing containing connection parameters, token expiry, and public key fingerprints.
* Local WebSocket transport with message validation, replay defense, and connection loss handling.
* Local Keychain integration on iOS and DPAPI-backed secure trust storage on Windows to handle credentials.

---

## File Deliverables

* **`Maxgravity-1.0-SideStore.ipa`**: The compiled iOS release package.
* **`Maxgravity-1.0-SideStore.sha256`**: SHA-256 integrity checksum.
* **`INSTALL_MAXGRAVITY_ON_IPHONE.md`**: Guide for sideloading using SideStore.

---

## Technical Specifications

* **Build Target**: iOS 17.0+
* **Architecture**: arm64 (iPhone hardware)
* **Private API Guard**: Active (Static validation confirms no forbidden UIKit/backbackdrop private selectors)
* **Accent Colors**: None (Zero blue product accents; green for success/online, amber for warnings/approvals, red for errors/deletions)
