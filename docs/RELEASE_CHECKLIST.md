# Release Checklist

Release under review: `1.0.8-native`

## Source And Build

- [x] Tracked worktree is clean before the package build.
- [x] Rust GUI tests pass: 38/38.
- [x] Rust formatting and Clippy with `-D warnings` pass.
- [x] C++ power-limit and power-policy tests pass.
- [x] Release build completes with the packaged icon present.
- [x] `native\verify-release.ps1 -NoBuild -VerifyShellIntegration
  -ExecuteNoChangePolicy` passes.
- [x] Package source commit and final SHA256 match the clean evidence.
- [ ] Hosted Windows CI passes for the release commit.
      Current blocker: GitHub Actions billing/spending-limit failure before job
      startup. Local release gates pass.

## Hardware Evidence

- [x] Read-only capability and telemetry pass on the verified 8845HS:
      SMU `15`, PM table `4c0009`, profile `hawk-point-8845hs`.
- [x] Controlled current-value Fast/Slow/STAPM write-back and read-back pass at
      `10/10/10 W`.
- [x] The worker disables policy and shuts down cleanly after the probe.
- [x] No second hardware owner remains after verification.
- [x] The deployed shortcut keeps the reviewed
      `--max-target-watts 10 --uniform-target-watts 10` arguments.
- [x] Local saved policy has both battery and AC at `10/10/10 W`.
- [ ] A second physical AMD laptop has read-only evidence.
- [ ] A fresh battery-to-AC-to-battery transition is re-run for this exact
      package revision. Historical transition evidence exists from earlier
      candidates.
- [x] Firmware-clamp behavior is documented instead of treated as a transport
      failure.

## Safety And Licensing

- [x] The portable package starts read-only by default.
- [x] Hardware writes require the explicit write-control flag.
- [x] Every write has a read-back, and Fast/Slow failures attempt restoration.
- [x] Existing process, mutex, and scheduled-task owners are documented.
- [x] The driver bootstrap reuses an existing valid WinRing0 service instead of
      replacing another installation's path.
- [x] The driver bootstrap waits for an app-owned service to reach `Stopped`
      before replacing its `.sys` file.
- [x] The driver uninstaller removes only the service whose binary path equals
      this application's ProgramData driver.
- [x] RyzenAdj, InpOut32, and WinRing0 notices are present in the ZIP.
- [x] Driver security behavior and unsigned-driver risks are documented.

## Package Verification

- [x] Portable ZIP builds from the recorded source commit.
- [x] ZIP SHA256 and source commit are recorded.
- [x] `SHA256SUMS.txt` verifies all 18 staged payload files.
- [x] First install, overwrite install, and uninstall pass in an isolated path.
- [x] Real current-user Start menu, Startup shortcut, and uninstall entry
      create/cleanup pass.
- [x] Packaged GUI and worker launch, tray lifecycle, single-instance wake,
      mode switch, preset editing, and diagnostics export pass.
- [x] DPI layout fixtures pass at 100%, 125%, and 150%.
- [x] Packaged compatibility collector produces sanitized JSON and Markdown.
- [x] No machine-specific diagnostics, logs, or user data are included.
- [x] Deployed `C:\RyzenAdj` payload matches all 18 staged files.
- [x] Deployment backup and recoverable repository copy exist.

## Documentation And Media

- [x] README status, package path, hash, driver setup, and safety scope match
      the current package.
- [x] Installation, recovery, deployment, and driver-cleanup instructions are
      current.
- [x] Supported-hardware wording does not claim universal support.
- [x] Native simple/advanced screenshots exist.
- [x] Promo video draft is rendered and machine-verified.
- [x] Bilibili cover exists and is machine-verified.
- [x] Local review bundle validates package, video, cover, and runtime drift.
- [ ] Project owner reviews the final video voice, pacing, claims, and cover.
- [ ] Bilibili title, description, cover, and tags are reviewed.

## Open External Gates

- [ ] Second AMD device compatibility evidence.
- [ ] Real 100% and 150% Windows system sessions; current capture uses
      test-only logical DPI fixtures.
- [ ] Hosted Windows CI.
- [ ] Clean Windows security-baseline WinRing0 verification.
- [ ] Human video and claim review.
- [ ] Explicit public-release approval.
- [ ] Authenticated human-operated GitHub Release and Bilibili upload.

## Final Publication

- [x] Consolidated native release dossier exists.
- [x] Draft GitHub release notes and Bilibili copy exist.
- [x] Release notes include safety limits and known risks.
- [ ] GitHub tag and asset list are reviewed.
- [ ] Bilibili upload uses an authenticated human-operated session.
- [ ] No login or credential prompt is automated.
- [ ] Project owner explicitly approves final publication.
