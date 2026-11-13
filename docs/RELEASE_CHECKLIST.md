# Release Checklist

Release under review: `1.0.29-native`

## Source And Build

- [x] Tracked worktree is clean before the package build.
- [x] Rust tests pass: 47/47 (23 GUI tests + 24 library tests).
- [x] Rust probe tests pass: 7/7.
- [x] Rust formatting and Clippy with `-D warnings` pass.
- [x] C++ power-limit and power-policy tests pass.
- [x] Release build completes with the packaged icon present.
- [x] `native\verify-release.ps1 -Version 1.0.29 -VerifyReproducibility
  -VerifyShellIntegration -ExecuteNoChangePolicy -VerifyWorkerHang
  -AllowBatteryWriteGuard`
  passes (AC session; the guard remained enabled).
- [x] Package source commit and final SHA256 match the clean evidence.
      Package SHA256 `c6b54d84f3f1bdba67407fe72a1f4465913e554defa1577e5c02c7373b5db640`,
      source commit `ee40565b66f6f8f0f52b362135604228fd2f7433`.
- [x] Rebuild from the same tree is byte-identical: GUI `d46f885e`, worker
      `67af1d41`, probe `9750418f`, ZIP `c6b54d84`.
- [x] Hosted Windows CI passes for the release commit
      (run `43514695587`, commit `5cfc357`).

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

- [x] Seven-scene promo v9 rendered at 1920x1080, 30 fps, 42.5 s, with burned-in
      captions, licensed music, and a real GUI recording.
- [x] Full FFmpeg decode, media evidence hashes, 8-frame contact sheet, and the
      1146x717 Bilibili cover are verified.
- [x] Real 1.0.28/1.0.29 GUI, consent-dialog, auto-policy, and device-panel
      captures are archived with the media evidence.
- [ ] Owner reviews pacing, voice, claims, and cover.
- [ ] Public GitHub Release and Bilibili upload (require explicit approval and
      an authenticated session).

## Safety And Licensing

- [x] The portable package starts read-only by default.
- [x] Hardware writes require the in-app lock or tray unlock consent; the CLI
      flag remains available for scripted starts.
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
