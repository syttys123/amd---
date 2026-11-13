# Documentation Index

Use this page as the entry point for project documentation. When documents
conflict, prefer the first applicable source in this order:

1. Current disk state, executable behavior, and fresh command/test output.
2. `DEV_STATUS.md`: implemented state, evidence, blockers, and next task.
3. Contracts and procedures: `IPC.md`, `PROFILES.md`, `SECURITY.md`, and
   `HARDWARE_TEST_PROCEDURE.md`.
4. Build and deployment guides: `BUILDING.md`, `PACKAGING.md`, and
   `DEPLOYMENT.md`.
5. Planning and rationale: `ROADMAP.md`, `ARCHITECTURE.md`, and `DECISIONS.md`.

## Start Here

| Document | Purpose |
|---|---|
| `DEV_STATUS.md` | Authoritative implemented state and next concrete task |
| `INSTALLATION.md` | Development package, install, upgrade, removal, and recovery |
| `MIGRATING_FROM_LEGACY.md` | Safe transition from the old RyzenPower task and worker |
| `SUPPORTED_HARDWARE.md` | Current compatibility scope and evidence limits |
| `COMPATIBILITY_REPORT_TEMPLATE.md` | Public hardware-evidence report format |
| `COMPATIBILITY_REPORTS.md` | Imported, sanitized read-only device reports |
| `HEADLESS_DIAGNOSTICS.md` | Packaged `amd-mobile-power-probe.exe` compatibility report without GUI or PowerShell |
| `SECURITY.md` | Hardware-write, driver, privilege, and data-safety model |
| `WINDOWS_DRIVER_SECURITY.md` | Current Windows, Defender, WinRing0, and signature evidence |
| `HARDWARE_MATRIX.md` | Device-level evidence |
| `HARDWARE_TEST_PROCEDURE.md` | Supervised first-write validation procedure |

## Architecture And Contracts

| Document | Purpose |
|---|---|
| `ARCHITECTURE.md` | Current process boundaries plus target architecture |
| `IPC.md` | Named-pipe protocol and command status |
| `PROFILES.md` | Platform profile schema and matching rules |
| `DECISIONS.md` | Accepted architecture decisions |

## UI And Design

| Document | Purpose |
|---|---|
| `UI_DESIGN_DATABASE.md` | Local design-system evidence, project tokens, component contracts, and the compact-window layout specification |
| `UI_SCREENSHOT_EVIDENCE.md` | Captured UI states, privacy boundary, and remaining media evidence |

The project-specific design database is derived from the read-only local corpus
at `<local-design-library>\design-corpus` and the SQLite index at
`<local-design-library>\ui-database`. The index is research evidence; the checked-in
Markdown document records the decisions that apply to AMD Mobile Power.

## Build And Release

| Document | Purpose |
|---|---|
| `BUILDING.md` | Native Rust/C++ build, legacy .NET build, and RyzenAdj prerequisites |
| `PACKAGING.md` | Native portable ZIP, driver scripts, and install/uninstall packaging |
| `DEPLOYMENT.md` | Promotion from development source to stable deployment |
| `THIRD_PARTY_NOTICES.md` | Third-party source and binary obligations |
| `LICENSING_REVIEW.md` | Engineering redistribution review and release license gates |
| `ROADMAP.md` | Milestones and release gates |
| `RELEASE_CHECKLIST.md` | Final publication checklist |
| `RELEASE_RUNBOOK.md` | Offline GitHub tag/Release and Bilibili upload procedure |
| `release-notes-1.0.30-zh.md` | Current public GitHub Release body draft |
| `release-assets-1.0.30.json` | Current package, video, cover, and copy manifest |
| `RELEASE_CANDIDATE_ZH.md` | Legacy .NET 1.0.4 package and historical review |
| `NATIVE_RELEASE_CANDIDATE_1.0.30_ZH.md` | Current native 1.0.30 package, evidence, and open-gate review |
| `NATIVE_RELEASE_CANDIDATE_1.0.29_ZH.md` | Historical native 1.0.29 review snapshot |
| `NATIVE_RELEASE_CANDIDATE_1.0.28_ZH.md` | Historical native 1.0.28 review snapshot |
| `NATIVE_RELEASE_CANDIDATE_ZH.md` | Historical native 1.0.23 review snapshot |
| `INTRODUCTION_ZH.md` | Chinese project introduction draft |
| `MEDIA_PLAN.md` | Screenshot, video, and Bilibili preparation plan |
| `PROMO_VIDEO.md` | Current video draft, render command, hashes, and media verification |
| `LAUNCH_COPY_ZH.md` | Review-only GitHub release and Bilibili publication copy |
| `NATIVE_LAUNCH_COPY_1.0.30_ZH.md` | Current review-only native 1.0.30 GitHub and Bilibili copy |
| `NATIVE_LAUNCH_COPY_1.0.29_ZH.md` | Historical native 1.0.29 launch copy |
| `NATIVE_LAUNCH_COPY_1.0.28_ZH.md` | Historical native 1.0.28 launch copy |
| `NATIVE_LAUNCH_COPY_ZH.md` | Historical native 1.0.23 launch-copy snapshot |

## Status Rules

- "Read-only" means the default process does not write power limits. It does not
  mean the source tree lacks write-capable code.
- A hardware write is not considered verified until read-back and restoration
  evidence is recorded in `HARDWARE_MATRIX.md`.
- A generated package is not a public release until every gate in
  `THIRD_PARTY_NOTICES.md`, `PACKAGING.md`, and `DEV_STATUS.md` passes.
