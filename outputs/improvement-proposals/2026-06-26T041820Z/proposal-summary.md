# Maxgravity Technical Improvement Proposals

This document provides a summary of the 60 improvement proposals compiled after the forensic audit and security remediation phase.

## Summary of Proposals by Area

| Area | Count | Focus |
|---|---|---|
| **UI/UX Improvements** | 15 | Transition animations, accessibility/dynamic styling, offline draft persistence, visual feedbacks, and typography polish. |
| **Bridge/Backend Improvements** | 15 | Process supervision, session buffering/recovery, git diff integrations, Bonjour/mDNS, and symmetric key rotations. |
| **New Product Features** | 10 | Dynamic roots management, schedulers, diagnostics bundle utilities, screenshot pipelines, and sandbox execution. |
| **Removals and Simplifications** | 10 | Legacy bypass routes, plaintext storage, mock fixtures, dead configurations, and insecure delegates. |
| **Testing/CI/Observability** | 10 | CLI mocks, expiry simulation, OpenTelemetry tracing, UI Automation testing, pre-commit scanners, and code coverage. |

---

## Key Proposals & Library Recommendations

### 1. Process Supervision (`BR01`)
- **Opportunity**: Antigravity CLI processes can hang without timeout.
- **Change**: Implement signal timeout handlers using `AbortController` natively in the adapter to kill hanging tasks.
- **Priority**: P1 | **Effort**: S

### 2. SQLite Registry (`BR02`)
- **Opportunity**: Plaintext files or scattered encrypted files have corruption risks.
- **Library**: `better-sqlite3` (Active, fast, transactional, single-file native DB).
- **Priority**: P2 | **Effort**: M

### 3. Local Bonjour/mDNS Discovery (`BR09`)
- **Opportunity**: Avoid requiring QR codes by advertising local HTTPS bridge presence.
- **Library**: `bonjour-service` (Highly maintained, cross-platform mDNS wrapper).
- **Priority**: P2 | **Effort**: M

### 4. Symmetric Secret Handshake Rotation (`BR12`)
- **Opportunity**: Storing static device secrets raises risk if keys are leaked.
- **Change**: Exchange a dynamic symmetric secret on every successful pairing handshake.
- **Priority**: P1 | **Effort**: M

---

## Priority and Effort Distribution

- **P0 (Security & Critical Deletions)**: 5 Items
- **P1 (Core UX & Stability)**: 12 Items
- **P2 (Enhanced UX & Backend Robustness)**: 33 Items
- **P3 (Optimizations & Future expansion)**: 10 Items

### Effort Profiles
- **XS**: 15 Items
- **S**: 25 Items
- **M**: 16 Items
- **L**: 3 Items
- **XL**: 1 Item

The complete item-by-item breakdown is located in [proposals.json](file:///c:/Users/kuroi/OneDrive/Desktop/Maxgravity/outputs/improvement-proposals/2026-06-26T041820Z/proposals.json).
