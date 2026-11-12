# Release Checklist

Release under review: `1.0.22-native`

## Source And Build

- [x] Tracked worktree is clean before the package build.
- [x] Rust tests pass: 44/44 (22 GUI tests + 22 library tests).
- [x] Rust probe tests pass: 7/7.
- [x] Rust formatting and Clippy with `-D warnings` pass.
- [x] C++ power-limit and power-policy tests pass.
- [x] Release build completes with the packaged icon present.
- [x] `native\verify-release.ps1 -Version 1.0.22-native -VerifyReproducibility
  -VerifyShellIntegration -ExecuteNoChangePolicy -VerifyWorkerHang
  -AllowBatteryWriteGuard`
  passes (AC session; the guard remained enabled).
- [x] Package source commit and final SHA256 match the clean evidence.
      Package SHA256 `500224c715e834e14a0134af681cf17171d24fb747d57515175688317fab3e76`,
      source commit `b688e50a337c399537ede69c42570d5c3b3013e0`.
- [x] Rebuild from the same tree is byte-identical: GUI `288f86de`, worker
      `67af1d41`, probe `9750418f`, ZIP `500224c7`.
- [ ] Hosted Windows CI passes for the release commit.
      Current blocker: GitHub Actions billing/spending-limit failure before job
      startup. Local release gates pass.

## Hardware Evidence

- [x] Read-only capability and telemetry pass on the verified 8845HS:
      SMU `15`, PM table `4c0009`, profile `hawk-point-8845hs`.
- [x] Controlled current-value policy probe passes on AC at `10/10/10 W`;
      policy disabled after.
- [x] The worker disables policy and shuts down cleanly after the probe.
- [x] No second hardware owner remains after verification.
- [x] The deployed shortcut keeps the reviewed
      `--enable-write-controls --simple-mode --max-target-watts 45` arguments.
- [x] Local presets are `10 / 25 / 45 W`, the automatic battery/AC policy is
      disabled, and `10 W` is the manual night preset.
- [ ] A second physical AMD laptop has read-only evidence.
- [ ] A fresh battery-to-AC-to-battery transition is re-run for this exact
      package revision. Historical transition evidence exists from earlier
      candidates.
- [x] Firmware-clamp behavior is documented instead of treated as a transport
      failure.
- [x] `-VerifyWorkerHang` passes against the expanded package: replacement in
      `34.6 s`, `22/22` responsive samples, zero failures, and `10/10/10 W`
      restored (the machine was already at 10 W, so no net change).

## UI Evidence

- [x] Packaged GUI interaction passes: modes, topmost, preset editing, target
      draft retention, focus-notification filtering, minimum bounds, advanced
      scrolling (wheel, scrollbar, focus reveal), diagnostics, minimize/restore
      cycles, close-to-tray, tray restore, single-instance wake.
- [x] Logical 100/125/150% layout fixtures match the exact client sizes.
- [x] The isolated 1366x768/200% work-area fixture passes for simple and
      advanced modes, including both scroll ranges and footer visibility.
- [x] Deployed GUI binary passes the same interaction suite.
- [ ] Real OS-level 100%/150% session and monitor-transition evidence.
- [x] Region-by-region screenshot review covers header, live power, target,
      presets, telemetry, status, editor, policy, device, high contrast, and
      long-error states.

## Release Media

- [x] Seven-scene promo draft rendered at 1920x1080, 107.7 s, with voice,
      original seeded music, captions, and contact sheet.
- [x] `verify-media.ps1` passes (full decode, volume, evidence hashes, review
      assets, and Bilibili cover).
- [x] 1.0.22 GUI, high-contrast, worker-offline, device-panel, contact-sheet,
      and Bilibili-cover assets are archived.
- [ ] Owner reviews pacing, voice, claims, and cover.
- [ ] Public GitHub Release and Bilibili upload (require explicit approval and
      an authenticated session).

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
