# Release Checklist

## Source And Build

- [x] Git worktree is clean.
- [x] `dotnet build AmdMobilePower.sln -c Release` passes with zero warnings.
- [x] `dotnet test AmdMobilePower.sln -c Release` passes.
- [x] `dotnet format AmdMobilePower.sln --verify-no-changes` passes.
- [x] Pinned RyzenAdj submodule commit is recorded.
- [ ] CI build for the release commit passes.
      Current blocker: GitHub Actions reports an account billing/spending-limit
      failure before the job starts. Local `verify-release.ps1` passes.

## Hardware Evidence

- [x] At least one controlled no-change write/read-back/restore test passes.
      Evidence:
      `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-2026-11-10.json`.
- [x] No hardware owner remains after the test.
- [ ] Battery and AC policy behavior is verified on real hardware.
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
- [x] No machine-specific diagnostics, logs, or user data are included.

## Documentation And Media

- [x] README status and feature list match the package.
- [x] Installation and recovery guide is current.
- [x] Supported-hardware wording does not claim universal support.
- [ ] Healthy dashboard, preset, conflict, diagnostics, and tray screenshots
      exist.
- [ ] Project introduction is reviewed.
- [ ] Promo video is rendered and reviewed.
- [ ] Bilibili title, description, cover, and tags are reviewed.

## Final Publication

- [ ] GitHub release tag and asset list are reviewed.
- [ ] Release notes include safety limits and known risks.
- [ ] Bilibili upload uses an authenticated human-operated session.
- [ ] No login, credential, or account-security prompt is automated.
- [ ] Project owner gives explicit approval for final publication.
