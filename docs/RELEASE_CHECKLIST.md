# Release Checklist

Release under review: `1.0.31-native`

Branch: `codex/atomic-state-persistence`

Status: `SOFTWARE_GATES_PASS_HARDWARE_GATE_PENDING`

## Source And Build

- [x] Branch worktree is clean before the candidate package build.
- [x] Rust tests pass: 51/51 (28 library + 23 GUI).
- [x] Rust probe tests pass: 7/7.
- [x] Rust formatting and Clippy with `-D warnings` pass.
- [x] C++ power-limit and power-policy tests pass.
- [x] Release build completes with the packaged icon present.
- [x] Package source commit and SHA256 match the clean evidence.
      SHA256 `ccb0ed9a91cc27ab068f117d8174c605c84fb4ab8f6202faecfdce2058326de5`,
      source commit `92c18216e610607a3139af5e4f4335e78a9f9129`.
- [x] Rebuild from the same tree is byte-identical: GUI `18f82690`, worker
      `67af1d41`, probe `9750418f`, ZIP `ccb0ed9a`.
- [x] Isolated install/overwrite/uninstall flow passes.
- [x] Installer process-scope regression passes while the deployed
      GUI/worker are running.
- [x] Hosted Windows CI passes for the native commit
      (run `43534100849`, commit `92c1821`).
- [x] Hosted Windows CI passes for the release-material commit
      (run `43535933200`, commit `fd45c21`).
- [x] Hosted Windows CI passes for the current branch HEAD
      (run `43537439992`, commit `fe8dcd7`).
- [ ] Full `verify-release.ps1 -Version 1.0.31` hardware gate.

## Hardware Evidence

- [ ] Read-only capability and telemetry are re-run for this exact package.
- [ ] Controlled current-value policy probe passes at the current safe limits.
- [ ] Worker-hang replacement and policy restore pass for this package.
- [ ] The worker disables policy and shuts down cleanly after the probe.
- [ ] No second hardware owner remains after verification.
- [ ] A fresh battery-to-AC-to-battery transition is re-run for this revision.
- [ ] A second physical AMD laptop has read-only evidence.
- [ ] Clean Windows WinRing0 baseline evidence is recorded.

## UI Evidence

- [x] Extracted packaged GUI lifecycle checks pass: modes, topmost, preset
      editing, target draft retention, focus notifications, minimum bounds,
      advanced scrolling, close-to-tray, tray restore, and single-instance
      wake.
- [x] Packaged UI evidence is recorded:
      `docs/evidence/ui/native-packaged-1.0.31-ui-2026-11-14.json`
      (`BackgroundGuiRelaunched=1`, `WriteControls=PASS`).
- [x] Logical 100/125/150% DPI fixtures are re-run for the 1.0.31 package.
- [x] The 1366x768/200% work-area fixture is re-run.
- [x] Maximize/scroll regression is re-run for the 1.0.31 package.
- [ ] Real OS-level 100%/150% sessions and monitor transitions are recorded.
- [ ] Deployed GUI binary passes the same interaction suite after promotion.

## Release Media

- [x] Seven-scene promo v9 is verified: 1920x1080, 30 fps, 42.5 s, burned-in
      captions, licensed music, and full `ffmpeg` decode.
- [x] Video, cover, and contact-sheet paths, sizes, and hashes match the
      1.0.31 release manifest.
- [x] 1.0.31 release notes, launch copy, candidate dossier, runbook, and media
      evidence are prepared.
- [ ] Owner reviews pacing, captions, claims, cover, and final copy.
- [ ] Public GitHub Release is explicitly approved.
- [ ] Bilibili upload is explicitly approved and uses an authenticated session.

## Safety And Licensing

- [x] The portable package starts read-only by default.
- [x] Hardware writes require the in-app lock or tray unlock consent.
- [x] Every write has a read-back; Fast/Slow failures attempt restoration.
- [x] Existing process, mutex, and scheduled-task owners are documented.
- [x] The driver bootstrap reuses an existing valid WinRing0 service.
- [x] The driver bootstrap waits for an app-owned service to reach `Stopped`.
- [x] The driver uninstaller removes only this installation's driver path.
- [x] RyzenAdj, InpOut32, and WinRing0 notices are present in the ZIP.
- [x] Driver security behavior and unsigned-driver risks are documented.

## Promotion

- [ ] Promotion dry run reviewed.
- [ ] Promotion applied with a timestamped recoverable backup.
- [ ] Deployed GUI/worker/probe hashes match the 1.0.31 deployment evidence.
- [ ] Shortcut arguments reviewed against `native/gui-cli-contract.json`.
- [ ] Publication readiness refreshed to `LocalReadiness=PASS` with no local
      blockers.
- [ ] Branch fast-forwarded into `main`.
