# Release Checklist

## Source And Build

- [x] Git worktree is clean.
- [x] `dotnet build AmdMobilePower.sln -c Release` passes with zero warnings.
- [x] `dotnet test --solution AmdMobilePower.sln -c Release` passes.
- [x] `dotnet format AmdMobilePower.sln --verify-no-changes` passes.
- [x] Direct and transitive NuGet vulnerability and deprecation audit passes.
      Evidence: `verify-dependencies.ps1`; six projects covered, zero advisories,
      zero deprecated packages.
- [x] Pinned RyzenAdj submodule commit is recorded.
- [ ] CI build for the release commit passes.
      Current blocker: GitHub Actions reports an account billing/spending-limit
      failure before the job starts. Local `verify-release.ps1` passes.

## Hardware Evidence

- [x] At least one controlled no-change write/read-back/restore test passes.
      Evidence:
      `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-2026-11-10.json`.
- [x] No hardware owner remains after the test.
- [x] Real battery read-only baseline and dashboard capture are recorded.
      Evidence:
      `mechrevo-wujie15-8845hs-battery-preflight-2026-11-10.json`.
- [x] Battery and AC policy behavior is verified on real hardware.
      Evidence:
      `docs/evidence/hardware/mechrevo-wujie15-8845hs-policy-2026-11-10.json`;
      12 W battery target, automatic AC restore, both baseline restores, and
      graceful worker shutdown passed.
- [x] Firmware clamps are documented rather than treated as transport failures.
- [ ] At least one second AMD platform has read-only evidence.
- [x] `HARDWARE_MATRIX.md` matches the tested release.

## Safety And Licensing

- [x] Default package remains read-only unless a deliberate release decision
      changes it.
- [x] Hardware-write flags and warning text are reviewed.
- [x] Conflict detection covers legacy process, mutex, and scheduled-task owners.
- [x] Hardware-timeout fail-closed behavior is verified.
- [x] RyzenAdj, InpOut32, and WinRing0 notices are present in the ZIP.
- [x] Driver security behavior is documented on the supported Windows version.
      Evidence: `docs/WINDOWS_DRIVER_SECURITY.md`.

## Package Verification

- [x] Portable ZIP builds from the clean release commit.
- [x] ZIP SHA256 and source commit are recorded.
- [x] `SHA256SUMS.txt` verifies every staged file.
- [x] First install, overwrite upgrade, and uninstall pass in an isolated path.
- [x] Start menu, uninstall entry, and logon startup behavior are verified.
      Evidence: `verify-shell-integration.ps1` passed; this host denied task
      registration, so the Startup-folder fallback path was exercised.
- [x] Packaged read-only compatibility collector produces sanitized JSON and
      closes its worker through the shutdown protocol.
      Evidence: `verify-release.ps1 -VerifyDiagnostics`; PowerShell 5.1 and 7
      host-side smoke tests.
- [x] Packaged simple dashboard has no target-left gray placeholder and reports
      the unified power-line label.
      Evidence: `verify-release.ps1 -VerifyDashboard`; live worker telemetry
      displayed `动态上限 25.0 W · 电源` with zero target-left artifact pixels.
- [ ] Packaged taskbar and notification-area lifecycle passes.
      Evidence pending: `verify-release.ps1 -VerifyUiLifecycle`.
- [x] No machine-specific diagnostics, logs, or user data are included.

## Documentation And Media

- [x] README status and feature list match the package.
- [x] Installation and recovery guide is current.
- [x] Supported-hardware wording does not claim universal support.
- [x] Healthy dashboard, preset, conflict, diagnostics, and tray screenshots
      exist.
- [x] Project introduction is fact-checked against current package evidence.
- [x] Promo video draft is rendered and machine-verified.
      Evidence: `PROMO_VIDEO.md` and `docs/evidence/media/promo-draft-2026-11-10.json`.
- [x] Bilibili 1146x717 cover is generated and machine-verified.
- [x] Local release-review bundle validates package, video, cover, and runtime
      drift, then writes complete SHA256 evidence without login or upload.
      Evidence: `prepare-release-review.ps1`; PowerShell 5.1 and 7 passed.
- [ ] Project owner reviews the final video voice, pacing, claims, and cover.
- [ ] Bilibili title, description, cover, and tags are reviewed.

## Final Publication

- [x] Consolidated release-candidate evidence dossier exists.
      Evidence: `RELEASE_CANDIDATE_ZH.md`.
- [x] Draft GitHub release notes and Bilibili publication copy are prepared.
      Evidence: `LAUNCH_COPY_ZH.md`; publication still requires human approval.
- [ ] GitHub release tag and asset list are reviewed.
- [x] Release notes include safety limits and known risks.
      Evidence: `LAUNCH_COPY_ZH.md`; draft covers firmware limits, driver blocks,
      interrupted recovery, power-bank detection, and experimental profiles.
- [ ] Bilibili upload uses an authenticated human-operated session.
- [ ] No login, credential, or account-security prompt is automated.
- [ ] Project owner gives explicit approval for final publication.
